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
    `src/Page/`,
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
  return `module Page.${pageModuleName} exposing (Model, Msg, Data, page)

${serverRender ? `import Server.Request as Request\n` : ""}
${withState ? "\nimport Browser.Navigation" : ""}
import DataSource exposing (DataSource)
import Head
import Head.Seo as Seo
import Page exposing (Page, PageWithState, StaticPayload)
${
  serverRender || withFallback
    ? "import PageServerResponse exposing (PageServerResponse)"
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

page : ${
    withState
      ? "PageWithState RouteParams Data Model Msg"
      : "Page RouteParams Data"
  }
page =
    ${
      serverRender
        ? `Page.serverRender
        { head = head
        , data = data
        }`
        : withFallback
        ? `Page.preRenderWithFallback { head = head
        , pages = pages
        , data = data
        }`
        : withParams
        ? `Page.preRender
        { head = head
        , pages = pages
        , data = data
        }`
        : `Page.single
        { head = head
        , data = data
        }`
    }
        |> ${
          withState
            ? `Page.buildWithLocalState
            { view = view
            , update = update
            , subscriptions = subscriptions
            , init = init
            }`
            : `Page.buildNoState { view = view }`
        }

${
  withState
    ? `
init :
    Maybe PageUrl
    -> Shared.Model
    -> StaticPayload Data RouteParams
    -> ( Model, Cmd Msg )
init maybePageUrl sharedModel static =
    ( {}, Cmd.none )


update :
    PageUrl
    -> Maybe Browser.Navigation.Key
    -> Shared.Model
    -> StaticPayload Data RouteParams
    -> Msg
    -> Model
    -> ${
      withState === "local"
        ? "( Model, Cmd Msg )"
        : "( Model, Cmd Msg, Maybe Shared.Msg )"
    }
update pageUrl maybeNavigationKey sharedModel static msg model =
    case msg of
        NoOp ->
            ${
              withState === "local"
                ? "( model, Cmd.none )"
                : "( model, Cmd.none, Nothing )"
            }


subscriptions : Maybe PageUrl -> RouteParams -> Path -> Model -> Sub Msg
subscriptions maybePageUrl routeParams path model =
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
    ? `data : RouteParams -> Request.ServerRequest (DataSource (PageServerResponse Data))
data routeParams =`
    : withFallback
    ? `data : RouteParams -> DataSource (PageServerResponse Data)
data routeParams =`
    : withParams
    ? `data : RouteParams -> DataSource Data
data routeParams =`
    : `data : DataSource Data
data =`
}
    ${
      serverRender
        ? `Request.succeed ()
        |> Request.thenRespond
            (\\() ->
                DataSource.succeed (PageServerResponse.RenderPage {})
            )
`
        : withFallback
        ? `    Data
        |> DataSource.succeed
        |> DataSource.map PageServerResponse.RenderPage
`
        : `DataSource.succeed {}`
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
