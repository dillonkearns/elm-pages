const path = require('path');
const glob = require('glob');

const root = path
  .resolve(__dirname, '../../')
  .replace(/.:/, '')
  .replace(/\\/g, '/');

module.exports = {
  findPreviewConfigurations
};

function findPreviewConfigurations() {
  return glob
    .sync(`${root}/preview*/**/elm.json`, {
      ignore: ['**/elm-stuff/**'],
      nodir: true
    })
    .map(path.dirname);
}
