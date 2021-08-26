#!/usr/bin/env node

const path = require('path');
const Ansi = require('./helpers/ansi');
const {execSync} = require('child_process');
const {findPreviewConfigurations} = require('./helpers/find-configurations');
const packageDependencies = require('../elm.json').dependencies;

const root = path.dirname(__dirname);

// Find all elm.json files

findPreviewConfigurations().forEach(checkThatExampleCompiles);

function checkThatExampleCompiles(exampleConfiguration) {
  const exampleConfigurationElmJson = require(`${exampleConfiguration}/elm.json`);

  checkDepsAreCompatible(
    path.basename(exampleConfiguration),
    exampleConfigurationElmJson.dependencies.direct
  );

  try {
    execSync(`npx elm-review --config ${exampleConfiguration} --report=json`, {
      encoding: 'utf8',
      stdio: 'pipe',
      cwd: path.resolve(__dirname, '..')
    }).toString();
    success(exampleConfiguration);
  } catch (error) {
    try {
      const output = JSON.parse(error.stdout);
      // We don't care whether there were any reported errors.
      // If the root type is not "error", then the configuration compiled
      // successfully, which is all we care about in this test.
      if (output.type !== 'review-errors') {
        console.log(
          `${Ansi.red('✖')} ${Ansi.yellow(
            `${path.relative(root, exampleConfiguration)}/`
          )} does not compile.`
        );
        console.log(
          `Please run
    ${Ansi.yellow(`npx elm-review --config ${exampleConfiguration}/`)}
and make the necessary changes to make it compile.`
        );
        process.exit(1);
      }

      success(exampleConfiguration);
      return;
    } catch {
      console.log(
        `An error occurred while trying to check whether the ${Ansi.yellow(
          path.relative(root, exampleConfiguration)
        )} configuration compiles.`
      );
      console.error(error);
      process.exit(1);
    }
  }
}

function success(config) {
  console.log(`${Ansi.green('✔')} ${path.relative(root, config)}/ compiles`);
}

function checkDepsAreCompatible(exampleConfiguration, previewDependencies) {
  Object.entries(packageDependencies).forEach(([depName, constraint]) => {
    if (!(depName in previewDependencies)) {
      console.error(
        `Dependency ${depName} is missing in the ${exampleConfiguration}/ configuration`
      );
      process.exit(1);
    }

    checkConstraint(
      exampleConfiguration,
      depName,
      constraint,
      previewDependencies[depName]
    );
    delete previewDependencies[depName];
  });

  const remainingKeys = Object.keys(previewDependencies);
  if (remainingKeys.length !== 0) {
    console.error(
      `There are extraneous dependencies in the ${exampleConfiguration}/ configuration: ${remainingKeys}`
    );
    process.exit(1);
  }
}

function checkConstraint(exampleConfiguration, depName, constraint, version) {
  const [minVersion] = constraint.split(' <= v < ').map(splitVersion);
  const previewVersion = splitVersion(version);
  const isValid =
    previewVersion[0] === minVersion[0] &&
    (previewVersion[1] > minVersion[1] ||
      (previewVersion[1] === minVersion[1] &&
        previewVersion[2] >= minVersion[2]));
  if (!isValid) {
    console.error(
      `The constraint for ${depName} in ${exampleConfiguration}/ is not in the expected range. It was ${version} but it should be in ${constraint} to be in sync with the package's elm.json's dependencies.`
    );
    process.exit(1);
  }
}

function splitVersion(version) {
  return version.split('.').map((n) => Number.parseInt(n, 10));
}
