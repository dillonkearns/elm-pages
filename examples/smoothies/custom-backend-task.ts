export async function environmentVariable(name) {
  const result = process.env[name];
  if (result) {
    return result;
  } else {
    throw `No environment variable called ${name}`;
  }
}

export async function hello(name) {
  return `Hello ${name}!`;
}

export async function hashPassword(password) {
  // Simplified for testing - just returns the password as-is
  return password;
}
