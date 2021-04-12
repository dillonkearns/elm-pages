#!/usr/bin/env node

const fs = require("./dir-helpers.js");
const path = require("path");
const routeHelpers = require("./route-codegen-helpers");

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
import Pages.ImagePath as ImagePath
import Head
import Head.Seo as Seo
import Pages.StaticHttp as StaticHttp
import Shared
import Template exposing (StaticPayload, Template, TemplateWithState)


type alias Model =
    ()


type alias Msg =
    Never

type alias RouteParams =
    ${routeHelpers.paramsRecord(templateName.split("."))}

template : Template RouteParams StaticData
template =
    Template.noStaticData
        { head = head
        , staticRoutes = StaticHttp.succeed []
        }
        |> Template.buildNoState { view = view }



head :
    StaticPayload StaticData RouteParams
    -> List Head.Tag
head static =
    Seo.summary
        { canonicalUrlOverride = Nothing
        , siteName = "elm-pages"
        , image =
            { url = ImagePath.build [ "TODO" ]
            , alt = "elm-pages logo"
            , dimensions = Nothing
            , mimeType = Nothing
            }
        , description = "TODO"
        , locale = Nothing
        , title = "TODO title" -- metadata.title -- TODO
        }
        |> Seo.website


type alias StaticData =
    ()


view :
    StaticPayload StaticData RouteParams
    -> Shared.PageView msg
view static =
    { title = "TODO title"
    , body = []
    }

`;
}

run();
