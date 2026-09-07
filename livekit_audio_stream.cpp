#include "livekit_audio_stream.h"

#include <godot_cpp/variant/utility_functions.hpp>
#include <godot_cpp/variant/packed_vector2_array.hpp>
#include <godot_cpp/variant/vector2.hpp>

using namespace godot;

void LiveKitAudioStream::_bind_methods() {
    ClassDB::bind_static_method("LiveKitAudioStream", D_METHOD("from_track", "track"), &LiveKitAudioStream::from_track);
    ClassDB::bind_static_method("LiveKitAudioStream", D_METHOD("from_participant", "participant", "source"), &LiveKitAudioStream::from_participant);

    ClassDB::bind_method(D_METHOD("get_sample_rate"), &LiveKitAudioStream::get_sample_rate);
    ClassDB::bind_method(D_METHOD("get_num_channels"), &LiveKitAudioStream::get_num_channels);
    ClassDB::bind_method(D_METHOD("poll", "playback", "max_frames"), &LiveKitAudioStream::poll, DEFVAL(256));
    ClassDB::bind_method(D_METHOD("close"), &LiveKitAudioStream::close);

    ADD_PROPERTY(PropertyInfo(Variant::INT, "sample_rate"), "", "get_sample_rate");
    ADD_PROPERTY(PropertyInfo(Variant::INT, "num_channels"), "", "get_num_channels");
}

LiveKitAudioStream::LiveKitAudioStream() {
    ring_.resize(kMaxAudioBufferSamples, 0.0f);
}

LiveKitAudioStream::~LiveKitAudioStream() {
    alive_->store(false);
    close();
}

void LiveKitAudioStream::_reader_loop() {
    // Capture a local copy so the native stream stays alive even if
    // close() calls stream_.reset() on another thread.
    auto stream = stream_;
    if (!stream) return;
    auto alive = alive_;
    while (running_.load() && alive->load()) {
        livekit::AudioFrameEvent event;
        bool ok = stream->read(event);
        if (!ok) {
            break;
        }
        if (!alive->load()) {
            break;
        }

        const auto &frame = event.frame;
        const auto &pcm_data = frame.data();
        int channels = frame.num_channels();

        // Update sample rate/channels from actual frame data
        sample_rate_ = frame.sample_rate();
        num_channels_ = channels;

        // Convert int16 interleaved PCM to float32 using persistent buffer.
        size_t sample_count = pcm_data.size();
        reader_float_samples_.resize(sample_count);
        for (size_t i = 0; i < sample_count; i++) {
            reader_float_samples_[i] = pcm_data[i] / 32768.0f;
        }

        {
            std::lock_guard<std::mutex> lock(audio_mutex_);
            size_t write_samples = sample_count;
            const float *src = reader_float_samples_.data();

            if (write_samples >= kMaxAudioBufferSamples) {
                // If incoming audio exceeds the buffer capacity, keep only the newest samples.
                src += (write_samples - kMaxAudioBufferSamples);
                write_samples = kMaxAudioBufferSamples;
                ring_head_ = 0;
                ring_tail_ = 0;
                ring_count_ = kMaxAudioBufferSamples;
                std::copy(src, src + write_samples, ring_.begin());
            } else {
                if (ring_count_ + write_samples > kMaxAudioBufferSamples) {
                    size_t overflow = ring_count_ + write_samples - kMaxAudioBufferSamples;
                    ring_head_ = (ring_head_ + overflow) % kMaxAudioBufferSamples;
                    ring_count_ = kMaxAudioBufferSamples;
                } else {
                    ring_count_ += write_samples;
                }

                size_t first_chunk = std::min(write_samples, kMaxAudioBufferSamples - ring_tail_);
                std::copy(src, src + first_chunk, ring_.begin() + ring_tail_);
                ring_tail_ = (ring_tail_ + first_chunk) % kMaxAudioBufferSamples;

                if (first_chunk < write_samples) {
                    size_t second_chunk = write_samples - first_chunk;
                    std::copy(src + first_chunk, src + write_samples, ring_.begin() + ring_tail_);
                    ring_tail_ = (ring_tail_ + second_chunk) % kMaxAudioBufferSamples;
                }
            }
        }
    }
}

Ref<LiveKitAudioStream> LiveKitAudioStream::from_track(const Ref<LiveKitTrack> &track) {
    if (track.is_null() || !track->get_native_track()) {
        UtilityFunctions::push_error("LiveKitAudioStream::from_track: invalid track");
        return Ref<LiveKitAudioStream>();
    }

    livekit::AudioStream::Options opts;

    auto native_stream = livekit::AudioStream::fromTrack(track->get_native_track(), opts);
    if (!native_stream) {
        UtilityFunctions::push_error("LiveKitAudioStream::from_track: failed to create stream");
        return Ref<LiveKitAudioStream>();
    }

    Ref<LiveKitAudioStream> stream;
    stream.instantiate();
    stream->stream_ = native_stream;
    stream->running_.store(true);
    // Capture the alive sentinel so the thread can detect if the object is freed.
    auto alive = stream->alive_;
    stream->reader_thread_.start([raw = stream.ptr(), alive]() {
        if (alive->load()) { raw->_reader_loop(); }
    });

    return stream;
}

Ref<LiveKitAudioStream> LiveKitAudioStream::from_participant(const Ref<LiveKitRemoteParticipant> &participant, int source) {
    if (participant.is_null() || !participant->get_native_remote_participant()) {
        UtilityFunctions::push_error("LiveKitAudioStream::from_participant: invalid participant");
        return Ref<LiveKitAudioStream>();
    }

    livekit::AudioStream::Options opts;

    auto native_stream = livekit::AudioStream::fromParticipant(
            *participant->get_native_remote_participant(),
            (livekit::TrackSource)source,
            opts);
    if (!native_stream) {
        UtilityFunctions::push_error("LiveKitAudioStream::from_participant: failed to create stream");
        return Ref<LiveKitAudioStream>();
    }

    Ref<LiveKitAudioStream> stream;
    stream.instantiate();
    stream->stream_ = native_stream;
    stream->running_.store(true);
    auto alive = stream->alive_;
    stream->reader_thread_.start([raw = stream.ptr(), alive]() {
        if (alive->load()) { raw->_reader_loop(); }
    });

    return stream;
}

int LiveKitAudioStream::get_sample_rate() const {
    return sample_rate_.load();
}

int LiveKitAudioStream::get_num_channels() const {
    return num_channels_.load();
}

int LiveKitAudioStream::poll(const Ref<AudioStreamGeneratorPlayback> &playback, int max_frames) {
    if (playback.is_null()) {
        return 0;
    }

    if (max_frames <= 0) {
        max_frames = 256;
    }

    int channels = num_channels_.load();
    if (channels <= 0) {
        channels = 1;
    }

    int available_frames = playback->get_frames_available();
    if (available_frames <= 0) {
        return 0;
    }

    const int max_safe_frames = std::min(max_frames, available_frames);
    const size_t max_safe_samples = static_cast<size_t>(max_safe_frames) * static_cast<size_t>(channels);
    if (max_safe_samples == 0) {
        return 0;
    }

    std::vector<float> buffer;
    size_t samples_to_push = 0;
    {
        std::lock_guard<std::mutex> lock(audio_mutex_);
        if (ring_count_ == 0) {
            return 0;
        }

        samples_to_push = std::min(ring_count_, max_safe_samples);
        if (samples_to_push == 0) {
            return 0;
        }

        buffer.resize(samples_to_push);
        if (ring_head_ + samples_to_push <= kMaxAudioBufferSamples) {
            std::copy(ring_.begin() + ring_head_, ring_.begin() + ring_head_ + samples_to_push, buffer.begin());
        } else {
            const size_t first_chunk = kMaxAudioBufferSamples - ring_head_;
            std::copy(ring_.begin() + ring_head_, ring_.end(), buffer.begin());
            std::copy(ring_.begin(), ring_.begin() + (samples_to_push - first_chunk), buffer.begin() + first_chunk);
        }
    }

    const int frames = static_cast<int>(samples_to_push / static_cast<size_t>(channels));
    if (frames <= 0) {
        return 0;
    }

    PackedVector2Array push_array;
    push_array.resize(frames);
    for (int i = 0; i < frames; i++) {
        const float left = buffer[i * channels];
        const float right = (channels > 1) ? buffer[i * channels + 1] : left;
        push_array.set(i, Vector2(left, right));
    }

    playback->push_buffer(push_array);

    {
        std::lock_guard<std::mutex> lock(audio_mutex_);
        if (samples_to_push >= ring_count_) {
            ring_head_ = 0;
            ring_tail_ = 0;
            ring_count_ = 0;
        } else {
            ring_head_ = (ring_head_ + samples_to_push) % kMaxAudioBufferSamples;
            ring_count_ -= samples_to_push;
        }
    }

    return frames;
}

void LiveKitAudioStream::close() {
    running_.store(false);
    if (stream_) {
        stream_->close();
    }
    reader_thread_.join_or_detach(2000);
    stream_.reset();
}
