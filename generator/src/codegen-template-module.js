const fs = require("./dir-helpers.js");
const path = require("path");
const routeHelpers = require("./route-codegen-helpers");

async function run({ moduleName, withState, serverRender, withFallback }) {
  if (!moduleName.match(/[A-Z][A-Za-z0-9]+(\.[A-Z][A-Za-z0-9])*/)) {
    console.error("Invalid module name.");
    process.exit(1);
  }
  const content = fileContent(
    moduleName,
    withState,
    serverRender,
    withFallback
  );
  const fullFilePath = path.join(
    `app/Route/`,
    moduleName.replace(/\./g, "/") + ".elm"
  );
  await fs.tryMkdir(path.dirname(fullFilePath));
  fs.writeFile(fullFilePath, content);
}

/**
 * @param {string} pageModuleName
 * @param {'local' | 'shared' | null} withState
 * @param {boolean} serverRender
 * @param {boolean} withFallback
 */
function fileContent(pageModuleName, withState, serverRender, withFallback) {
  return fileContentWithParams(
    pageModuleName,
    routeHelpers.routeParams(pageModuleName.split(".")).length > 0,
    withState,
    serverRender,
    withFallback
  );
}

/**
 * @param {string} pageModuleName
 * @param {boolean} withParams
 * @param {'local' | 'shared' | null} withState
 * @param {boolean} serverRender
 * @param {boolean} withFallback
 */
function fileContentWithParams(
  pageModuleName,
  withParams,
  withState,
  serverRender,
  withFallback
) {
  return `module Route.${pageModuleName} exposing (Model, Msg, Data, route)

${serverRender ? `import Server.Request as Request\n` : ""}
${withState ? "\nimport Effect exposing (Effect)" : ""}
import DataSource exposing (DataSource)
${serverRender ? `import ErrorPage exposing (ErrorPage)` : ""}
import Head
import Head.Seo as Seo
import RouteBuilder exposing (StatelessRoute, StatefulRoute, StaticPayload)
${
  serverRender || withFallback
    ? "import Server.Response as Response exposing (Response)"
    : ""
}
import Pages.PageUrl exposing (PageUrl)
import Pages.Url
import Shared
${withState ? "import Path exposing (Path)\n" : ""}
import View exposing (View)


type alias Model =
    {}


${
  withState
    ? `type Msg
    = NoOp`
    : `type alias Msg =
    ()`
}

type alias RouteParams =
    ${routeHelpers.paramsRecord(pageModuleName.split("."))}

route : ${
    withState
      ? "StatefulRoute RouteParams Data Model Msg"
      : "StatelessRoute RouteParams Data"
  }
route =
    ${
      serverRender
        ? `RouteBuilder.serverRender
        { head = head
        , data = data
        }`
        : withFallback
        ? `RouteBuilder.preRenderWithFallback { head = head
        , pages = pages
        , data = data
        }`
        : withParams
        ? `RouteBuilder.preRender
        { head = head
        , pages = pages
        , data = data
        }`
        : `RouteBuilder.single
        { head = head
        , data = data
        }`
    }
        |> ${
          withState
            ? `RouteBuilder.buildWithLocalState
            { view = view
            , update = update
            , subscriptions = subscriptions
            , init = init
            }`
            : `RouteBuilder.buildNoState { view = view }`
        }

${
  withState
    ? `
init :
    Maybe PageUrl
    -> Shared.Model
    -> StaticPayload Data RouteParams
    -> ( Model, Effect Msg )
init maybePageUrl sharedModel static =
    ( {}, Effect.none )


update :
    PageUrl
    -> Shared.Model
    -> StaticPayload Data RouteParams
    -> Msg
    -> Model
    -> ${
      withState === "local"
        ? "( Model, Effect Msg )"
        : "( Model, Effect Msg, Maybe Shared.Msg )"
    }
update pageUrl sharedModel static msg model =
    case msg of
        NoOp ->
            ${
              withState === "local"
                ? "( model, Effect.none )"
                : "( model, Effect.none, Nothing )"
            }


subscriptions : Maybe PageUrl -> RouteParams -> Path -> Shared.Model -> Model -> Sub Msg
subscriptions maybePageUrl routeParams path sharedModel model =
    Sub.none
`
    : ""
}

${
  withParams || withFallback
    ? `pages : DataSource (List RouteParams)
pages =
    DataSource.succeed []


`
    : ""
}
type alias Data =
    {}


${
  serverRender
    ? `data : RouteParams -> Request.Parser (DataSource (Response Data ErrorPage))
data routeParams =`
    : withFallback
    ? `data : RouteParams -> DataSource (Response Data ErrorPage)
data routeParams =`
    : withParams
    ? `data : RouteParams -> DataSource Data
data routeParams =`
    : `data : DataSource Data
data =`
}
    ${
      serverRender
        ? `Request.succeed (DataSource.succeed (Response.render Data))
`
        : withFallback
        ? `    Data
        |> DataSource.succeed
        |> DataSource.map Response.render
`
        : `DataSource.succeed Data`
    }

head :
    StaticPayload Data RouteParams
    -> List Head.Tag
head static =
    Seo.summary
        { canonicalUrlOverride = Nothing
        , siteName = "elm-pages"
        , image =
            { url = Pages.Url.external "TODO"
            , alt = "elm-pages logo"
            , dimensions = Nothing
            , mimeType = Nothing
            }
        , description = "TODO"
        , locale = Nothing
        , title = "TODO title" -- metadata.title -- TODO
        }
        |> Seo.website



${
  withState
    ? `view :
    Maybe PageUrl
    -> Shared.Model
    -> templateModel
    -> StaticPayload templateData routeParams
    -> View templateMsg
view maybeUrl sharedModel model static =
`
    : `view :
    Maybe PageUrl
    -> Shared.Model
    -> StaticPayload Data RouteParams
    -> View Msg
view maybeUrl sharedModel static =`
}
    View.placeholder "${pageModuleName}"
`;
}

module.exports = { run };
