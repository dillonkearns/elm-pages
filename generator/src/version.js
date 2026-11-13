/**
 * @param {number[]} version - for example [1, 4, 0]
 * @param {number[]} minimum
 * @returns {boolean} whether `version` is older than `minimum`
 */
export function isOlderVersion(version, minimum) {
  for (let i = 0; i < minimum.length; i++) {
    if (version[i] !== minimum[i]) {
      return version[i] < minimum[i];
    }
  }
  return false;
}
