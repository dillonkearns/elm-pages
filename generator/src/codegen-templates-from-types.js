#!/usr/bin/env node

const fs = require("./dir-helpers.js");
const ElmModuleParser = require("elm-module-parser");
const path = require("path");
const readline = require("readline");
const rl = readline.createInterface(process.stdin, process.stdout);
const { templateTypesModuleName } = require("./constants.js");

const templateModulePath = `./src/${templateTypesModuleName}.elm`;

async function exposedTypes() {
  const fileContents = await fs.readFile(templateModulePath);
  const result = ElmModuleParser.parseElmModule(fileContents);
  const exposedTypes = result.types.map((exposedType) => {
    return {
      exposed:
        result.exposes_all ||
        result.exposing
          .map((exposed) => exposed.name)
          .includes(exposedType.name),
      name: exposedType.name,
    };
  });
  const templateModules = await fs.readdir(`./src/Template/`);
  const moduleNames = templateModules.map((fileName) =>
    path.basename(fileName, ".elm")
  );

  const unexposedTypeNames = exposedTypes
    .filter((module) => !module.exposed)
    .map((module) => module.name);
  const exposedTypeNames = exposedTypes
    .filter((module) => module.exposed)
    .map((module) => module.name);
  const staleModules = difference(moduleNames, exposedTypeNames);
  const staleBecauseNotExposedModules = intersection(
    unexposedTypeNames,
    staleModules
  );
  const unexposedNoMatchingTemplate = difference(
    unexposedTypeNames,
    staleModules
  );
  const staleBecauseNoType = difference(
    staleModules,

    staleBecauseNotExposedModules
  );
  const missingModules = difference(exposedTypeNames, moduleNames);

  if (staleModules.length === 0) {
    if (missingModules.length === 0) {
      console.log(
        "Success! No work to do, Template Modules are all up-to-date."
      );
      if (unexposedNoMatchingTemplate.length > 0) {
        console.log(
          "\nI don't generate Template Modules for types that are not exposed, but there are some unexposed types in your TemplateTypeDefinitions.elm:\n\n",
          unexposedNoMatchingTemplate
        );
        console.log(
          "\n\nYou can expose these types and re-run this script to generate Template Modules for those types."
        );
      }
      console.log(
        "\n\nIf you'd like to add a new Template Module, create a new exposed type to TemplateTypeDefinitions.elm then re-running this script."
      );

      process.exit(0);
    } else {
      console.log(
        "My plan is to generate the following modules: ",
        missingModules.join("\n")
      );
      rl.question("Overwrite? [Y]/n: ", async function (answer) {
        if (answer === "y" || answer == "") {
          console.log("Generating...", missingModules);
          await writeTemplateModules(missingModules);
          process.exit(0);
        } else {
          console.log(
            "Didn't generate any modules. Re-run and answer yes to create missing template modules."
          );
          process.exit(0);
        }
      });
    }
  } else {
    if (missingModules.length > 0) {
      console.log(
        "There are some mismatched items in both the Template Module files in src/Template/ and the types in TemplateTypeDefinitions.elm. If you're renaming a type or a module, be sure to change both the type name and the module name.\n"
      );
      console.log("I have modules but no types for these", staleModules);
      console.log("\nI have types but no modules for these", missingModules);
      process.exit(1);
    }
    if (staleBecauseNotExposedModules.length > 0) {
      console.log(
        "The following modules have a type defined in TemplateTypeDefinitions.elm as well as a corresponding Template Module in src/Template/, but the type is not exposed:\n\n",
        staleBecauseNotExposedModules
      );
      console.log(
        "\nYou can get them in sync by either exposing the type in TemplateTypeDefinitions.elm, or by deleting the corresponding Template Module file from src/Template/."
      );
    }
    if (staleBecauseNoType.length > 0) {
      console.log(
        "The following modules have a module in src/Template/, but no corresponding type in TemplateTypeDefinitions.elm:\n\n",
        staleBecauseNoType
      );
      console.log(
        "\nYou can fix them by either defining a corresponding type in TemplateTypeDefinitions, or by deleting the Template Module file from src/Template/."
      );
    }
    process.exit(1);
  }

  // TODO if there are exposed types with type variables, exit(1)

  return result;
}

/**
 * @param {string[]} array1
 * @param {string[]} array2
 */
function difference(array1, array2) {
  return array1.filter((value) => !array2.includes(value));
}
function intersection(arrA, arrB) {
  return arrA.filter((x) => arrB.includes(x));
}

/**
 * @param {string[]} typeNames
 */
async function writeTemplateModules(typeNames) {
  await fs.tryMkdir("src/Template");
  await Promise.all(
    typeNames.map(async (typeName) => {
      await fs.writeFile(
        `src/Template/${typeName}.elm`,
        tempateModuleFileContent(typeName)
      );
    })
  );
}

/**
 * @param {string} templateName
 */
function tempateModuleFileContent(templateName) {
  return `
module Template.${templateName} exposing (Model, Msg, template)

import Head
import Pages
import Pages.PagePath exposing (PagePath)
import Shared
import Template exposing (StaticPayload, Template)
import ${templateTypesModuleName} exposing (${templateName})
import TemplateType exposing (TemplateType)


type alias Model =
    ()


type alias Msg =
    Never


type alias StaticData =
    ()


template : Template ${templateName} StaticData
template =
    Template.noStaticData { head = head }
        |> Template.buildNoState { view = view }


head :
    StaticPayload ${templateName} StaticData
    -> List (Head.Tag Pages.PathKey)
head { metadata } =
    []


view :
    List ( PagePath Pages.PathKey, TemplateType )
    -> StaticPayload ${templateName} StaticData
    -> Shared.RenderedBody
    -> Shared.PageView msg
view allMetadata static rendered =
    { title = Debug.todo "Add title."
    , body =
        []
    }

`;
}

exposedTypes();
