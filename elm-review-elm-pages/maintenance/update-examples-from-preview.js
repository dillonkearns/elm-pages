#!/usr/bin/env node

const path = require('path');
const fs = require('fs-extra');
const root = path.resolve(__dirname, '..');
const packageElmJson = require(`${root}/elm.json`);
const {
  findPreviewConfigurations
} = require('../elm-review-package-tests/helpers/find-configurations');

if (require.main === module) {
  copyPreviewsToExamples();
} else {
  module.exports = copyPreviewsToExamples;
}

// Find all elm.json files

function copyPreviewsToExamples() {
  const previewFolders = findPreviewConfigurations();
  previewFolders.forEach(copyPreviewToExample);
}

function copyPreviewToExample(pathToPreviewFolder) {
  const pathToExampleFolder = `${pathToPreviewFolder}/`.replace(
    /preview/g,
    'example'
  );
  fs.removeSync(pathToExampleFolder);
  fs.copySync(pathToPreviewFolder, pathToExampleFolder, {overwrite: true});

  const pathToElmJson = path.resolve(pathToExampleFolder, 'elm.json');
  const elmJson = fs.readJsonSync(pathToElmJson);

  // Remove the source directory pointing to the package's src/
  elmJson['source-directories'] = elmJson['source-directories'].filter(
    (sourceDirectory) =>
      path.resolve(pathToExampleFolder, sourceDirectory) !==
      path.resolve(root, 'src')
  );
  elmJson.dependencies.direct[packageElmJson.name] = packageElmJson.version;
  fs.writeJsonSync(pathToElmJson, elmJson, {spaces: 4});
}
