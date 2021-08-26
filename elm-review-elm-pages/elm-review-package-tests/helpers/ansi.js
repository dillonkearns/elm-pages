module.exports = {
  red,
  green,
  yellow
};

function red(text) {
  return '\u001B[31m' + text + '\u001B[39m';
}

function green(text) {
  return '\u001B[32m' + text + '\u001B[39m';
}

function yellow(text) {
  return '\u001B[33m' + text + '\u001B[39m';
}
