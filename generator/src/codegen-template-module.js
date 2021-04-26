const fs = require("./dir-helpers.js");
const path = require("path");
const routeHelpers = require("./route-codegen-helpers");

async function run({ moduleName }) {
  if (!moduleName.match(/[A-Z][A-Za-z0-9]+(\.[A-Z][A-Za-z0-9])*/)) {
    console.error("Invalid module name.");
    process.exit(1);
  }
  const content = fileContent(moduleName);
  const fullFilePath = path.join(
    `src/Page/`,
    moduleName.replace(/\./g, "/") + ".elm"
  );
  await fs.tryMkdir(path.dirname(fullFilePath));
  fs.writeFile(fullFilePath, content);
}

/**
 * @param {string} pageModuleName
 */
function fileContent(pageModuleName) {
  return routeHelpers.routeParams(pageModuleName.split(".")).length > 0
    ? fileContentWithParams(pageModuleName)
    : fileContentWithoutParams(pageModuleName);
}

/**
 * @param {string} pageModuleName
 */
function fileContentWithParams(pageModuleName) {
  return `module Page.${pageModuleName} exposing (Model, Msg, Data, page)

import Element exposing (Element)
import Document exposing (Document)
import Pages.ImagePath as ImagePath
import Head
import Head.Seo as Seo
import DataSource exposing (DataSource)
import Shared
import Page exposing (StaticPayload, Page, PageWithState)


type alias Model =
    ()


type alias Msg =
    Never

type alias RouteParams =
    ${routeHelpers.paramsRecord(pageModuleName.split("."))}

page : Page RouteParams Data
page =
    Page.prerenderedRoute
        { head = head
        , routes = routes
        , data = data
        }
        |> Page.buildNoState { view = view }


routes : DataSource (List RouteParams)
routes =
    DataSource.fail "Add some routes"


data : RouteParams -> DataSource Data
data routeParams =
    DataSource.succeed ()



head :
    StaticPayload Data RouteParams
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


type alias Data =
    ()


view :
    StaticPayload Data RouteParams
    -> Document Msg
view static =
    Document.placeholder "${pageModuleName}"
`;
}

/**
 * @param {string} pageModuleName
 */
function fileContentWithoutParams(pageModuleName) {
  return `module Page.${pageModuleName} exposing (Model, Msg, Data, page)

import Element exposing (Element)
import Document exposing (Document)
import Pages.ImagePath as ImagePath
import Head
import Head.Seo as Seo
import DataSource exposing (DataSource)
import Shared
import Page exposing (StaticPayload, Page, PageWithState)


type alias Model =
    ()


type alias Msg =
    Never

type alias RouteParams =
    {}

page : Page RouteParams Data
page =
    Page.singleRoute
        { head = head
        , data = data
        }
        |> Page.buildNoState { view = view }


data : DataSource Data
data =
    DataSource.succeed ()



head :
    StaticPayload Data RouteParams
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


type alias Data =
    ()


view :
    StaticPayload Data RouteParams
    -> Document Msg
view static =
    Document.placeholder "${pageModuleName}"
`;
}

module.exports = { run };
