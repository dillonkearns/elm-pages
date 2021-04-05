#!/usr/bin/env node

const fs = require("./dir-helpers.js");
const path = require("path");

async function run() {
  if (process.argv.length === 3) {
    const moduleName = process.argv[2];
    if (!moduleName.match(/[A-Z][A-Za-z0-9]+(\.[A-Z][A-Za-z0-9])*/)) {
      console.error("Invalid module name.");
      process.exit(1);
    }
    const content = fileContent(moduleName);
    const fullFilePath = path.join(
      `src/Template/`,
      moduleName.replace(".", "/") + ".elm"
    );
    await fs.tryMkdir(path.dirname(fullFilePath));
    fs.writeFile(fullFilePath, content);
  } else {
    console.error(`Unexpected CLI options: ${process.argv}`);
    process.exit(1);
  }
}

function fileContent(templateName) {
  return `module Template.${templateName} exposing (Model, Msg, template)

import Element exposing (Element)
import Element.Region
import Head
import Head.Seo as Seo
import Pages exposing (images)
import Pages.PagePath exposing (PagePath)
import Shared
import Site
import Template exposing (StaticPayload, Template, TemplateWithState)


type alias Model =
    ()


type alias Msg =
    Never


template : Template {} ()
template =
    Template.noStaticData { head = head }
        |> Template.buildNoState { view = view }


head :
    StaticPayload ()
    -> List (Head.Tag Pages.PathKey)
head static =
    Seo.summary
        { canonicalUrlOverride = Nothing
        , siteName = "elm-pages"
        , image =
            { url = images.iconPng
            , alt = "elm-pages logo"
            , dimensions = Nothing
            , mimeType = Nothing
            }
        , description = Site.tagline
        , locale = Nothing
        , title = "TODO title" -- metadata.title -- TODO
        }
        |> Seo.website


type alias StaticData =
    ()


view :
    StaticPayload StaticData
    -> Shared.PageView msg
view static =
    { title = "TODO title"
    , body = []
    }

`;
}

run();
