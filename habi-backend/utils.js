// Authentication Utilities
// Helper functions for Firebase authentication and validation

export const validateEmail = (email) => {
  const emailRegex = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
  return emailRegex.test(email);
};

export const validateUID = (uid) => {
  return uid && uid.length > 0 && uid.length <= 128;
};

export const validateMood = (mood) => {
  const validMoods = ['happy', 'sad', 'anxious', 'excited', 'calm', 'angry', 'neutral'];
  return validMoods.includes(mood.toLowerCase());
};

export const validateIntensity = (intensity) => {
  return intensity >= 1 && intensity <= 10 && Number.isInteger(intensity);
};

// Error response formatter
export const errorResponse = (res, statusCode, message) => {
  return res.status(statusCode).json({ 
    error: true, 
    message, 
    timestamp: new Date().toISOString() 
  });
};

// Success response formatter
export const successResponse = (res, statusCode, data) => {
  return res.status(statusCode).json({ 
    error: false, 
    data,
    timestamp: new Date().toISOString() 
  });
};
