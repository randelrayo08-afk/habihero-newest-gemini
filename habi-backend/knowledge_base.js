export const knowledgeBaseEntries = [
  {
    id: 'math-wide-coverage',
    category: 'Tutor Brain',
    title: 'Math - Broad Coverage',
    patterns: [/math/i, /number/i, /addition/i, /add\b/i, /subtraction/i, /subtract/i, /multiplication/i, /multiply/i, /times\b/i, /division/i, /divide/i, /divided by/i, /fraction/i, /decimal/i, /percent/i, /ratio/i, /variable/i, /equation/i, /problem/i, /geometry/i, /area/i, /perimeter/i, /volume/i, /angle/i, /measure/i, /graph/i, /statistics/i, /probability/i, /algebra/i, /function/i, /calculus/i, /mean/i, /median/i, /mode/i, /average/i, /order/i, /largest/i, /smallest/i, /maximum/i, /minimum/i, /sum\b/i, /difference\b/i, /product\b/i, /quotient\b/i],
    summary: 'Help students with a wide range of math topics, from basic arithmetic to more advanced concepts.',
    content: `The AI companion can support many math topics, not just Grade 6. This includes basic arithmetic, fractions, decimals, percentages, ratios, algebra, geometry, measurement, statistics, probability, functions, and introductory calculus ideas. Explain ideas in clear, simple language, with examples and step-by-step reasoning. For arithmetic problems, show how to break them into smaller steps. For word problems, help students find the important numbers, choose the right operation, and check the answer. For advanced topics, keep explanations grounded in examples and what the question is asking.`
  },
  {
    id: 'grade6-math-problem-solving',
    category: 'Tutor Brain',
    title: 'Grade 6 Math - Problem Solving',
    patterns: [/word problem/i, /solve/i, /expression/i, /equation/i, /sum/i, /difference/i, /product/i, /quotient/i, /how much/i, /how many/i, /what is/i],
    summary: 'Guide students through solving math problems step by step.',
    content: `When solving a math problem, read it carefully, underline the important numbers, choose the correct operation, and write your steps clearly. Encourage students to draw a picture if it helps, use simple numbers first, and check the answer by working the problem again in a different way.`
  },
  {
    id: 'grade6-science-space',
    category: 'Tutor Brain',
    title: 'Grade 6 Science - Earth and Space',
    patterns: [/planet/i, /solar system/i, /earth/i, /space/i],
    summary: 'Provide simple explanations for Earth, planets, and basic science concepts.',
    content: `Earth is our home planet in the solar system. It has land, water, and air. The Sun is the center of our solar system, and Earth moves around it once each year.`
  },
  {
    id: 'grade6-english-reading',
    category: 'Tutor Brain',
    title: 'Grade 6 English - Reading and Writing',
    patterns: [/story/i, /reading/i, /write/i, /grammar/i],
    summary: 'Support reading comprehension, vocabulary, and writing in a friendly, age-appropriate voice.',
    content: `Grade 6 English focuses on understanding stories, using vocabulary correctly, and writing clear sentences. Help students by breaking ideas into small steps, asking them what the main idea is, and showing them how to organize their thoughts.`
  },
  {
    id: 'habit-brain-routines',
    category: 'Habit Brain',
    title: 'Healthy Habits and Daily Routines',
    patterns: [/habit/i, /routine/i, /study/i, /homework/i, /sleep/i],
    summary: 'Encourage good habits, study routines, and healthy daily choices.',
    content: `A good student routine includes a morning check, a short study session, a healthy snack, and a calm bedtime. Encourage students to set a small daily goal, like reading for 15 minutes, practicing one math problem, or writing three sentences in their journal.`
  },
  {
    id: 'motivation-brain',
    category: 'Motivation Brain',
    title: 'Motivation Messages and Praise',
    patterns: [/good job/i, /well done/i, /try again/i, /encourage/i, /proud/i],
    summary: 'Use encouraging words and celebrate effort, not just results.',
    content: `Praise the student for trying, learning, and being brave. Say things like "You are doing your best," "That’s a great effort," and "Keep going; every step helps you learn."` 
  },
  {
    id: 'quiz-brain',
    category: 'Quiz Brain',
    title: 'Quiz Templates and Questions',
    patterns: [/quiz/i, /question/i, /test/i, /practice/i],
    summary: 'Generate simple practice questions and review answers with explanation.',
    content: `Offer short, simple questions: a multiple-choice math problem, a reading comprehension question, or a vocabulary activity. After the student answers, give a kind review and explain the right answer in simple words.`
  },
  {
    id: 'emotion-brain',
    category: 'Emotion Brain',
    title: 'Emotion Support and Empathy',
    patterns: [/sad/i, /happy/i, /worried/i, /afraid/i, /alone/i, /stress/i],
    summary: 'Respond with empathy and help the student feel supported.',
    content: `Listen carefully to feelings, say you understand, and offer a calm response. Use phrases like "I’m here for you," "It’s okay to feel that way," and "Let’s take a deep breath and try one small step together."`
  },
  {
    id: 'memory-brain',
    category: 'Memory Brain',
    title: 'Remembering Progress and Preferences',
    patterns: [/remember/i, /again/i, /last time/i, /favorite/i],
    summary: 'Personalize replies based on the student’s learning progress and preferences.',
    content: `This app remembers the student’s progress, favorite subjects, and achievements. Use that information to make future help feel personal and supportive.`
  },
  {
    id: 'game-brain',
    category: 'Game Brain',
    title: 'Habi Hero Game Rules and Rewards',
    patterns: [/quest/i, /badge/i, /reward/i, /hero/i, /game/i],
    summary: 'Describe Habi Hero game elements, quests, and badge rewards.',
    content: `Habi Hero uses quests, badges, and rewards to make learning fun. Explain how completing tasks earns points, badges, and story progress in a friendly way.`
  }
];

export function getRelevantKnowledgeBaseText(message) {
  const text = String(message || '').toLowerCase();
  const matches = knowledgeBaseEntries.filter((entry) =>
    entry.patterns.some((pattern) => pattern.test(text))
  );

  if (!matches.length) {
    return null;
  }

  return matches
    .map((entry) => `Knowledge Base Entry: ${entry.title}\nCategory: ${entry.category}\n${entry.summary}\n${entry.content}`)
    .join('\n\n');
}
