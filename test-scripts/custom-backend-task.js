export async function environmentVariable(input) {
  input.mutable++;
  return "Done";
}

// End-to-end smoke tests for BackendTask.Custom.runBytes.
// echoBytes: returns the input unchanged, proving the wire is round-tripping.
export async function echoBytes(inputBytes) {
  return inputBytes;
}

// reverseBytes: returns the input reversed, proving JS can transform the payload.
export async function reverseBytes(inputBytes) {
  return Buffer.from(inputBytes).reverse();
}
