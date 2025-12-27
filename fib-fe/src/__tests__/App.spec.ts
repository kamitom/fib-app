import { describe, it, expect, beforeEach, vi, afterEach } from 'vitest'
import { mount, flushPromises } from '@vue/test-utils'
import App from '../App.vue'

// Mock fetch globally
const mockFetch = vi.fn()
global.fetch = mockFetch

describe('App.vue', () => {
  beforeEach(() => {
    vi.clearAllMocks()
    vi.useFakeTimers()
  })

  afterEach(() => {
    vi.restoreAllMocks()
    vi.useRealTimers()
  })

  describe('Initial load', () => {
    it('fetches seen indices and calculated values on mount', async () => {
      mockFetch
        .mockResolvedValueOnce({
          ok: true,
          json: async () => [1, 2, 3]
        })
        .mockResolvedValueOnce({
          ok: true,
          json: async () => ({ '1': '1', '2': '1', '3': '2' })
        })

      const wrapper = mount(App)
      await flushPromises()

      expect(mockFetch).toHaveBeenCalledTimes(2)
      expect(mockFetch).toHaveBeenCalledWith('/api/values/all')
      expect(mockFetch).toHaveBeenCalledWith('/api/values/current')

      expect(wrapper.text()).toContain('1, 2, 3')
      expect(wrapper.text()).toContain('For index 1 I calculated 1')
    })

    it('displays "None" when no indices seen', async () => {
      mockFetch
        .mockResolvedValueOnce({
          ok: true,
          json: async () => []
        })
        .mockResolvedValueOnce({
          ok: true,
          json: async () => ({})
        })

      const wrapper = mount(App)
      await flushPromises()

      expect(wrapper.text()).toContain('None')
      expect(wrapper.text()).toContain('No values calculated yet')
    })

    it('handles fetch errors gracefully', async () => {
      const consoleError = vi.spyOn(console, 'error').mockImplementation(() => {})
      mockFetch.mockRejectedValue(new Error('Network error'))

      mount(App)
      await flushPromises()

      expect(consoleError).toHaveBeenCalledWith(
        'Failed to fetch seen indices:',
        expect.any(Error)
      )

      consoleError.mockRestore()
    })
  })

  describe('Form submission', () => {
    beforeEach(() => {
      mockFetch
        .mockResolvedValueOnce({ ok: true, json: async () => [] })
        .mockResolvedValueOnce({ ok: true, json: async () => ({}) })
    })

    it('submits valid index successfully', async () => {
      mockFetch.mockResolvedValueOnce({
        ok: true,
        json: async () => {}
      })
      mockFetch.mockResolvedValueOnce({
        ok: true,
        json: async () => [5]
      })

      const wrapper = mount(App)
      await flushPromises()

      const input = wrapper.find('input[type="number"]')
      const button = wrapper.find('button')

      await input.setValue('5')
      await button.trigger('click')
      await flushPromises()

      expect(mockFetch).toHaveBeenCalledWith('/api/values', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ index: 5 })
      })

      // Input should be cleared after submission
      expect(input.element.value).toBe('')
    })

    it('rejects negative numbers', async () => {
      const alertMock = vi.spyOn(window, 'alert').mockImplementation(() => {})

      const wrapper = mount(App)
      await flushPromises()

      const input = wrapper.find('input[type="number"]')
      const button = wrapper.find('button')

      await input.setValue('-5')
      await button.trigger('click')

      expect(alertMock).toHaveBeenCalledWith('Please enter a valid non-negative number')
      expect(mockFetch).toHaveBeenCalledTimes(2) // Only initial fetches

      alertMock.mockRestore()
    })

    it('rejects index > 40', async () => {
      const alertMock = vi.spyOn(window, 'alert').mockImplementation(() => {})

      const wrapper = mount(App)
      await flushPromises()

      const input = wrapper.find('input[type="number"]')
      const button = wrapper.find('button')

      await input.setValue('41')
      await button.trigger('click')

      expect(alertMock).toHaveBeenCalledWith('Index too high (max 40)')

      alertMock.mockRestore()
    })

    it('rejects non-numeric input', async () => {
      const alertMock = vi.spyOn(window, 'alert').mockImplementation(() => {})

      const wrapper = mount(App)
      await flushPromises()

      const input = wrapper.find('input[type="number"]')
      const button = wrapper.find('button')

      await input.setValue('abc')
      await button.trigger('click')

      expect(alertMock).toHaveBeenCalledWith('Please enter a valid non-negative number')

      alertMock.mockRestore()
    })

    it('handles server errors', async () => {
      const alertMock = vi.spyOn(window, 'alert').mockImplementation(() => {})
      mockFetch.mockResolvedValueOnce({
        ok: false,
        json: async () => ({ detail: 'Server error' })
      })

      const wrapper = mount(App)
      await flushPromises()

      const input = wrapper.find('input[type="number"]')
      const button = wrapper.find('button')

      await input.setValue('5')
      await button.trigger('click')
      await flushPromises()

      expect(alertMock).toHaveBeenCalledWith('Server error')

      alertMock.mockRestore()
    })

    it('submits on Enter key', async () => {
      mockFetch.mockResolvedValueOnce({
        ok: true,
        json: async () => {}
      })
      mockFetch.mockResolvedValueOnce({
        ok: true,
        json: async () => [10]
      })

      const wrapper = mount(App)
      await flushPromises()

      const input = wrapper.find('input[type="number"]')

      await input.setValue('10')
      await input.trigger('keyup.enter')
      await flushPromises()

      expect(mockFetch).toHaveBeenCalledWith('/api/values', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ index: 10 })
      })
    })
  })

  describe('Polling mechanism', () => {
    it('polls for calculated values every 2 seconds', async () => {
      mockFetch
        .mockResolvedValue({
          ok: true,
          json: async () => ({})
        })

      mount(App)
      await flushPromises()

      // Initial fetch: 2 calls
      expect(mockFetch).toHaveBeenCalledTimes(2)

      // Fast-forward 2 seconds
      vi.advanceTimersByTime(2000)
      await flushPromises()

      // Should have called fetchCalculatedValues again
      expect(mockFetch).toHaveBeenCalledTimes(3)

      // Fast-forward another 2 seconds
      vi.advanceTimersByTime(2000)
      await flushPromises()

      expect(mockFetch).toHaveBeenCalledTimes(4)
    })

    it('polls after successful submission', async () => {
      mockFetch
        .mockResolvedValueOnce({ ok: true, json: async () => [] })
        .mockResolvedValueOnce({ ok: true, json: async () => ({}) })
        .mockResolvedValueOnce({ ok: true, json: async () => {} }) // POST response
        .mockResolvedValueOnce({ ok: true, json: async () => [5] }) // fetchSeenIndices
        .mockResolvedValueOnce({ ok: true, json: async () => ({ '5': '5' }) }) // Poll after 100ms

      const wrapper = mount(App)
      await flushPromises()

      const input = wrapper.find('input[type="number"]')
      const button = wrapper.find('button')

      await input.setValue('5')
      await button.trigger('click')
      await flushPromises()

      // Fast-forward 100ms for the setTimeout poll
      vi.advanceTimersByTime(100)
      await flushPromises()

      expect(mockFetch).toHaveBeenCalledWith('/api/values/current')
    })
  })

  describe('Display logic', () => {
    it('renders multiple calculated values correctly', async () => {
      mockFetch
        .mockResolvedValueOnce({
          ok: true,
          json: async () => [1, 2, 5]
        })
        .mockResolvedValueOnce({
          ok: true,
          json: async () => ({
            '1': '1',
            '2': '1',
            '5': '5'
          })
        })

      const wrapper = mount(App)
      await flushPromises()

      const text = wrapper.text()
      expect(text).toContain('For index 1 I calculated 1')
      expect(text).toContain('For index 2 I calculated 1')
      expect(text).toContain('For index 5 I calculated 5')
    })
  })
})
