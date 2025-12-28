<script setup lang="ts">
  import { ref, onMounted } from 'vue'

  const API_BASE = '/api'

  const index = ref<string>('')
  const seenIndices = ref<number[]>([])
  const calculatedValues = ref<Record<string, string>>({})

  async function fetchSeenIndices() {
    try {
      const res = await fetch(`${API_BASE}/values/all`)
      const data = await res.json()
      seenIndices.value = data
    } catch (err) {
      console.error('Failed to fetch seen indices:', err)
    }
  }

  async function fetchCalculatedValues() {
    try {
      const res = await fetch(`${API_BASE}/values/current`)
      const data = await res.json()
      calculatedValues.value = data
    } catch (err) {
      console.error('Failed to fetch calculated values:', err)
    }
  }

  async function handleSubmit() {
    const idx = parseInt(index.value)

    if (isNaN(idx) || idx < 0) {
      alert('Please enter a valid non-negative number')
      return
    }

    if (idx > 40) {
      alert('Index too high (max 40)')
      return
    }

    try {
      const res = await fetch(`${API_BASE}/values`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ index: idx })
      })

      if (!res.ok) {
        const err = await res.json()
        alert(err.detail || 'Failed to submit')
        return
      }

      index.value = ''
      await fetchSeenIndices()

      // Poll for result
      setTimeout(fetchCalculatedValues, 100)
    } catch (err) {
      console.error('Failed to submit:', err)
    }
  }

  onMounted(() => {
    fetchSeenIndices()
    fetchCalculatedValues()

    // Polling every 2 seconds
    setInterval(() => {
      fetchCalculatedValues()
    }, 2000)
  })

  function renderCalculatedValues(): string {
    const entries = Object.entries(calculatedValues.value)
    if (entries.length === 0) return 'No values calculated yet'

    return entries
      .map(([idx, val]) => `For index ${idx} I calculated ${val}`)
      .join('\n')
  }
</script>

<template>
  <div class="container">
    <header>
      <h1>Fib Calculator - v01</h1>
    </header>

    <main>
      <div class="input-section">
        <label for="index-input">Enter your index:</label>
        <input id="index-input" v-model="index" type="number" min="0" max="40" @keyup.enter="handleSubmit" />
        <button @click="handleSubmit">Submit</button>
      </div>

      <div class="output-section">
        <div class="indices">
          <h2>Indices I have seen:</h2>
          <p>{{ seenIndices.length > 0 ? seenIndices.join(', ') : 'None' }}</p>
        </div>

        <div class="values">
          <h2>Calculated Values:</h2>
          <pre>{{ renderCalculatedValues() }}</pre>
        </div>
      </div>
    </main>
  </div>
</template>

<style scoped>
  .container {
    max-width: 800px;
    margin: 0 auto;
    padding: 20px;
    font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
  }

  header {
    text-align: center;
    padding: 20px 0;
    border-bottom: 2px solid #333;
    margin-bottom: 30px;
  }

  h1 {
    margin: 0;
    font-size: 2em;
  }

  .input-section {
    display: flex;
    align-items: center;
    gap: 10px;
    margin-bottom: 40px;
    font-size: 1.1em;
  }

  label {
    font-weight: 500;
  }

  input[type="number"] {
    width: 100px;
    padding: 8px 12px;
    font-size: 1em;
    border: 2px solid #333;
    border-radius: 4px;
  }

  button {
    padding: 8px 20px;
    font-size: 1em;
    background: #333;
    color: white;
    border: none;
    border-radius: 4px;
    cursor: pointer;
    font-weight: 500;
  }

  button:hover {
    background: #555;
  }

  .output-section {
    display: flex;
    flex-direction: column;
    gap: 30px;
  }

  h2 {
    font-size: 1.3em;
    margin-bottom: 10px;
  }

  .indices p {
    font-size: 1.1em;
    line-height: 1.6;
  }

  .values pre {
    background: #f5f5f5;
    padding: 15px;
    border-radius: 4px;
    font-size: 1em;
    line-height: 1.8;
    white-space: pre-wrap;
  }
</style>
