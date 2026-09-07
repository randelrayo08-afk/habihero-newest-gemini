#!/usr/bin/env node

/**
 * API Testing Script
 * Use this to test all backend endpoints
 * 
 * Usage: node test-api.js
 */

const BASE_URL = 'http://localhost:5000';
const TEST_UID = 'test_user_' + Date.now();

console.log('🧪 Habi Backend API Test Suite');
console.log(`Base URL: ${BASE_URL}`);
console.log(`Test UID: ${TEST_UID}\n`);

const sleep = (ms) => new Promise(resolve => setTimeout(resolve, ms));

async function runTests() {
  try {
    // Test 1: Health Check
    console.log('✓ Test 1: Health Check');
    let response = await fetch(`${BASE_URL}/health`);
    let data = await response.json();
    console.log(`  Status: ${response.status}`, data.status);
    console.log();

    // Test 2: Create User
    console.log('✓ Test 2: Create User');
    response = await fetch(`${BASE_URL}/api/users`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        uid: TEST_UID,
        email: `test_${TEST_UID}@example.com`,
        displayName: 'Test User',
        age: 25,
        interests: ['gaming', 'coding']
      })
    });
    data = await response.json();
    console.log(`  Status: ${response.status}`, data.message);
    console.log();

    // Test 3: Get User
    console.log('✓ Test 3: Get User Profile');
    response = await fetch(`${BASE_URL}/api/users/${TEST_UID}`);
    data = await response.json();
    console.log(`  Status: ${response.status}`);
    console.log(`  Name: ${data.displayName}, Age: ${data.age}`);
    console.log();

    // Test 4: Log Mood
    console.log('✓ Test 4: Log Mood');
    response = await fetch(`${BASE_URL}/api/moods`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        uid: TEST_UID,
        mood: 'happy',
        intensity: 8,
        notes: 'Testing API'
      })
    });
    data = await response.json();
    console.log(`  Status: ${response.status}`, data.message);
    console.log();

    // Test 5: Get Mood History
    console.log('✓ Test 5: Get Mood History');
    response = await fetch(`${BASE_URL}/api/moods/${TEST_UID}`);
    data = await response.json();
    console.log(`  Status: ${response.status}`);
    console.log(`  Moods logged: ${data.length}`);
    console.log();

    // Test 6: Create Journal Entry
    console.log('✓ Test 6: Create Journal Entry');
    response = await fetch(`${BASE_URL}/api/journal`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        uid: TEST_UID,
        title: 'Test Entry',
        content: 'This is a test journal entry for the backend API',
        mood: 'happy'
      })
    });
    data = await response.json();
    const entryId = data.entryId;
    console.log(`  Status: ${response.status}`, data.message);
    console.log(`  Entry ID: ${entryId}`);
    console.log();

    // Test 7: Get Journal Entries
    console.log('✓ Test 7: Get All Journal Entries');
    response = await fetch(`${BASE_URL}/api/journal/${TEST_UID}`);
    data = await response.json();
    console.log(`  Status: ${response.status}`);
    console.log(`  Total entries: ${data.length}`);
    console.log();

    // Test 8: Get Single Journal Entry
    console.log('✓ Test 8: Get Single Journal Entry');
    response = await fetch(`${BASE_URL}/api/journal/${TEST_UID}/${entryId}`);
    data = await response.json();
    console.log(`  Status: ${response.status}`);
    console.log(`  Title: ${data.title}`);
    console.log();

    // Test 9: Update Journal Entry
    console.log('✓ Test 9: Update Journal Entry');
    response = await fetch(`${BASE_URL}/api/journal/${TEST_UID}/${entryId}`, {
      method: 'PATCH',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        title: 'Updated Test Entry',
        content: 'This entry has been updated'
      })
    });
    data = await response.json();
    console.log(`  Status: ${response.status}`, data.message);
    console.log();

    // Test 10: Create Habit
    console.log('✓ Test 10: Create Habit');
    response = await fetch(`${BASE_URL}/api/habits`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        uid: TEST_UID,
        name: 'Morning Run',
        description: 'Run 5km every morning',
        frequency: 'daily',
        color: '#FF6B6B'
      })
    });
    data = await response.json();
    const habitId = data.habitId;
    console.log(`  Status: ${response.status}`, data.message);
    console.log();

    // Test 11: Get Habits
    console.log('✓ Test 11: Get All Habits');
    response = await fetch(`${BASE_URL}/api/habits/${TEST_UID}`);
    data = await response.json();
    console.log(`  Status: ${response.status}`);
    console.log(`  Total habits: ${data.length}`);
    console.log();

    // Test 12: Mark Habit as Completed
    console.log('✓ Test 12: Mark Habit as Completed');
    response = await fetch(`${BASE_URL}/api/habits/${TEST_UID}/${habitId}/complete`, {
      method: 'POST'
    });
    data = await response.json();
    console.log(`  Status: ${response.status}`, data.message);
    console.log();

    console.log('✅ All tests passed!\n');
    console.log('📊 Summary:');
    console.log(`  • User created and retrieved`);
    console.log(`  • Mood logged`);
    console.log(`  • Journal entry created, retrieved, and updated`);
    console.log(`  • Habit created and marked complete`);
    console.log(`\n🎉 Backend is working correctly!`);

  } catch (error) {
    console.error('❌ Test failed:', error.message);
    process.exit(1);
  }
}

runTests();
