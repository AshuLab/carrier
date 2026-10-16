// Ctrl+C: stop the engine without waiting for stages, then free the instance lock and leave.
export function stopOnSigint({ engine, close }: { engine: { shutdown(): Promise<void> }; close: () => void }) {
  process.once('SIGINT', async () => {
    let code = 0;
    try {
      await engine.shutdown();
    } catch (error) {
      console.error('Shutdown failed:', error);
      code = 1;
    } finally {
      close();
    }
    process.exit(code);
  });
}
