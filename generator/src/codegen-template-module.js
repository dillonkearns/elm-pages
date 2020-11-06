#!/usr/bin/env node

const fs = require("./dir-helpers.js");
const { templateTypesModuleName } = require("./constants.js");

if (process.argv.length === 3) {
  const moduleName = process.argv[2];
  if (!moduleName.match(/[A-Z][A-Za-z0-9]*/)) {
    console.error("Invalid module name.");
    process.exit(1);
  }
  const content = fileContent(moduleName);
  fs.tryMkdir("src/Template");
  fs.writeFile(`src/Template/${moduleName}.elm`, content);
} else {
  console.error(`Unexpected CLI options: ${process.argv}`);
  process.exit(1);
}

function fileContent(templateName) {
  return `
module Template.${templateName} exposing (template)

import Head
import Pages
import Pages.PagePath exposing (PagePath)
import Shared
import Template exposing (StaticPayload, Template)
import ${templateTypesModuleName} exposing (${templateName})
import TemplateType exposing (TemplateType)


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
