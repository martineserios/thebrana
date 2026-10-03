import { expect, test } from 'claude-code/testing'

test('good-minimal sets a status from run()', async ($, on) => {
  let status: unknown = null
  on('session.start', (_$, e) => ({ cwd: e.cwd }))
  on('process.run', () => ({ value: { exitCode: 0, stdout: '[]', stderr: '' } }))
  on('ui.status', (_$, e) => {
    status = e.text
    return { value: undefined }
  })
  await $.session.start({ surface: 'terminal', isInteractive: true, cwd: '/w' })
  expect(status).toBe('good-minimal: ok')
})
