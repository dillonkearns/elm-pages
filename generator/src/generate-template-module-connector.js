const globby = require("globby");
const path = require("path");
const mm = require("micromatch");
const routeHelpers = require("./route-codegen-helpers");

/**
 * @param {string} basePath
 * @param {'browser' | 'cli'} phase
 */
function generateTemplateModuleConnector(basePath, phase) {
  const templates = globby.sync(["app/Route/**/*.elm"], {}).map((file) => {
    const captures = mm.capture("app/Route/**/*.elm", file);
    if (captures) {
      return path.join(captures[0], captures[1]).split(path.sep);
    } else {
      return [];
    }
  });
  if (templates.length <= 0) {
    throw {
      path: "",
      name: "Main",
      problems: [
        {
          title: "Could not generate entrypoint",
          message: [
            `I couldn't find any Page Templates. Try creating your first page by running: \n\n`,
            {
              bold: false,
              underline: false,
              color: "yellow",
              string: "elm-pages add Index",
            },
          ],
        },
      ],
    };
  }

  return {
    mainModule: `port module Main exposing (..)

import Api
import Bytes exposing (Bytes)
import Bytes.Decode
import Bytes.Encode
import Dict
import Effect exposing (Effect)
import ErrorPage exposing (ErrorPage)
import HtmlPrinter
import Lamdera.Wire3
import Pages.FormState
import Pages.Internal.String
import Pages.Internal.Platform.ToJsPayload
import Pages.Internal.ResponseSketch exposing (ResponseSketch)
import Pages.Msg
import Server.Response
import ApiRoute
import Browser.Navigation
import Route exposing (Route)
import Http
import Json.Decode
import Json.Encode
import Pages.Flags
import Pages.Fetcher
import ${
      phase === "browser"
        ? "Pages.Internal.Platform"
        : "Pages.Internal.Platform.Cli"
    }
import Shared
import Site
import Head
import Html exposing (Html)
import Pages.Internal.NotFoundReason
import Pages.Transition
import Pages.PageUrl exposing (PageUrl)
import Path exposing (Path)
import Pages.Internal.RoutePattern
import Pages.ProgramConfig
import Url
import DataSource exposing (DataSource)
import QueryParams
import Task exposing (Task)
import Url exposing (Url)
import View

${templates.map((name) => `import Route.${name.join(".")}`).join("\n")}


type alias Model =
    { global : Shared.Model
    , page : PageModel
    , current :
        Maybe
            { path :
                { path : Path
                , query : Maybe String
                , fragment : Maybe String
                }
            , metadata : Maybe Route
            , pageUrl : Maybe PageUrl
            }
    }


type PageModel
    = ${templates
      .map(
        (name) =>
          `Model${pathNormalizedName(name)} Route.${moduleName(name)}.Model\n`
      )
      .join("    | ")}
    | ModelErrorPage____ ErrorPage.Model
    | NotFound




type Msg
    = MsgGlobal Shared.Msg
    | OnPageChange
        { protocol : Url.Protocol
        , host : String
        , port_ : Maybe Int
        , path : Path
        , query : Maybe String
        , fragment : Maybe String
        , metadata : Maybe Route
        }
    | MsgErrorPage____ ErrorPage.Msg
    | ${templates
      .map(
        (name) =>
          `Msg${pathNormalizedName(name)} Route.${moduleName(name)}.Msg\n`
      )
      .join("    | ")}


type PageData
    = Data404NotFoundPage____
    | DataErrorPage____ ErrorPage
    | ${templates
      .map(
        (name) =>
          `Data${pathNormalizedName(name)} Route.${moduleName(name)}.Data\n`
      )
      .join("    | ")}


type ActionData
    = 
    ${templates
      .map(
        (name) =>
          `ActionData${pathNormalizedName(name)} Route.${moduleName(
            name
          )}.ActionData\n`
      )
      .join("    | ")}


view :
    Pages.FormState.PageFormState
    -> Dict.Dict String Pages.Transition.FetcherState
    -> Maybe Pages.Transition.Transition
    -> { path : Path
    , route : Maybe Route
    }
    -> Maybe PageUrl
    -> Shared.Data
    -> PageData
    -> Maybe ActionData
    ->
        { view : Model -> { title : String, body : Html (Pages.Msg.Msg Msg) }
        , head : List Head.Tag
        }
view pageFormState fetchers transition page maybePageUrl globalData pageData actionData =
    case ( page.route, pageData ) of
        ( _, DataErrorPage____ data ) ->
            { view =
                \\model ->
                    case model.page of
                        ModelErrorPage____ subModel ->
                            ErrorPage.view data subModel
                                --maybePageUrl
                                --model.global
                                ----subModel
                                --{ data = data
                                --, sharedData = globalData
                                --, routeParams = {}
                                --, path = page.path
                                --}
                                |> View.map (MsgErrorPage____ >> Pages.Msg.UserMsg)
                                |> Shared.template.view globalData page model.global (MsgGlobal >> Pages.Msg.UserMsg)

                        _ ->
                            { title = "Model mismatch", body = Html.text <| "Model mismatch" }
            , head = []
            }



        ${templates
          .map(
            (name) =>
              `( Just ${
                emptyRouteParams(name)
                  ? `Route.${routeHelpers.routeVariant(name)}`
                  : `(Route.${routeHelpers.routeVariant(name)} s)`
              }, Data${routeHelpers.routeVariant(name)} data ) ->
                  let
                      actionDataOrNothing =
                          case actionData of
                              Just (ActionData${routeHelpers.routeVariant(
                                name
                              )} justActionData) -> Just justActionData
                              _ -> Nothing
                  in
                  { view =
                      \\model ->
                          case model.page of
                              Model${pathNormalizedName(name)} subModel ->
                                  Route.${moduleName(name)}.route.view
                                      maybePageUrl
                                      model.global
                                      subModel
                                      { data = data
                                      , sharedData = globalData
                                      , routeParams = ${
                                        emptyRouteParams(name) ? "{}" : "s"
                                      }
                                      , action = actionDataOrNothing
                                      , path = page.path
                                      , submit = Pages.Fetcher.submit Route.${moduleName(
                                        name
                                      )}.w3_decode_ActionData
                                      , transition = transition
                                      , fetchers = fetchers
                                      , pageFormState = pageFormState
                                      }
                                      |> View.map (Pages.Msg.map Msg${pathNormalizedName(
                                        name
                                      )})
                                      |> Shared.template.view globalData page model.global (MsgGlobal >> Pages.Msg.UserMsg)

                              _ ->
                                  { title = "Model mismatch", body = Html.text <| "Model mismatch" }
                  , head = ${
                    phase === "browser"
                      ? "[]"
                      : `Route.${moduleName(name)}.route.head
                      { data = data
                      , sharedData = globalData
                      , routeParams = ${emptyRouteParams(name) ? "{}" : "s"}
                      , action = Nothing
                      , path = page.path
                      , submit = Pages.Fetcher.submit Route.${moduleName(
                        name
                      )}.w3_decode_ActionData
                      , transition = Nothing -- TODO is this safe?
                      , fetchers = Dict.empty -- TODO is this safe?
                      , pageFormState = Dict.empty -- TODO is this safe?
                      }
                      `
                  }
                  }
`
          )
          .join("\n\n        ")}
        _ ->
            { head = []
            , view =
                \\_ ->
                    { title = "Page not found"
                    , body =
                            Html.div [] 
                            [ Html.text "This page could not be found."
                            ]
                    }

            }



init :
    Maybe Shared.Model
    -> Pages.Flags.Flags
    -> Shared.Data
    -> PageData
    -> Maybe ActionData
    -> Maybe Browser.Navigation.Key
    ->
        Maybe
            { path :
                { path : Path
                , query : Maybe String
                , fragment : Maybe String
                }
            , metadata : Maybe Route
            , pageUrl : Maybe PageUrl
            }
    -> ( Model, Effect Msg )
init currentGlobalModel userFlags sharedData pageData actionData navigationKey maybePagePath =
    let
        ( sharedModel, globalCmd ) =
            currentGlobalModel |> Maybe.map (\\m -> ( m, Effect.none )) |> Maybe.withDefault (Shared.template.init userFlags maybePagePath)

        ( templateModel, templateCmd ) =
            case ( ( Maybe.map2 Tuple.pair (maybePagePath |> Maybe.andThen .metadata) (maybePagePath |> Maybe.map .path) ), pageData ) of
                ${templates
                  .map(
                    (name) => `( Just ( ${
                      emptyRouteParams(name)
                        ? `Route.${routeHelpers.routeVariant(name)}`
                        : `(Route.${routeHelpers.routeVariant(
                            name
                          )} routeParams)`
                    }, justPath ), Data${pathNormalizedName(
                      name
                    )} thisPageData ) ->
                    let
                        actionDataOrNothing =
                            case actionData of
                                Just (ActionData${routeHelpers.routeVariant(
                                  name
                                )} justActionData) -> Just justActionData
                                _ -> Nothing
                    in
                    Route.${moduleName(name)}.route.init
                        (Maybe.andThen .pageUrl maybePagePath)
                        sharedModel
                        { data = thisPageData
                        , sharedData = sharedData
                        , action = actionDataOrNothing
                        , routeParams = ${
                          emptyRouteParams(name) ? "{}" : "routeParams"
                        }
                        , path = justPath.path
                        , submit = Pages.Fetcher.submit Route.${moduleName(
                          name
                        )}.w3_decode_ActionData
                        , transition = Nothing -- TODO is this safe, will this always be Nothing?
                        , fetchers = Dict.empty
                        , pageFormState = Dict.empty
                        }
                        |> Tuple.mapBoth Model${pathNormalizedName(
                          name
                        )} (Effect.map Msg${pathNormalizedName(name)})
`
                  )
                  .join("\n                ")}
                _ ->
                    (case pageData of
                        DataErrorPage____ errorPage ->
                            errorPage

                        _ ->
                            ErrorPage.notFound
                    )
                        |> ErrorPage.init
                        |> Tuple.mapBoth ModelErrorPage____ (Effect.map MsgErrorPage____)
    in
    ( { global = sharedModel
      , page = templateModel
      , current = maybePagePath
      }
    , Effect.batch
        [ templateCmd
        , globalCmd |> Effect.map MsgGlobal
        ]
    )



update : Pages.FormState.PageFormState  -> Dict.Dict String Pages.Transition.FetcherState -> Maybe Pages.Transition.Transition -> Shared.Data -> PageData -> Maybe Browser.Navigation.Key -> Msg -> Model -> ( Model, Effect Msg )
update pageFormState fetchers transition sharedData pageData navigationKey msg model =
    case msg of
        MsgErrorPage____ msg_ ->
            let
                ( updatedPageModel, pageCmd ) =
                    case ( model.page, pageData ) of
                        ( ModelErrorPage____ pageModel, DataErrorPage____ thisPageData ) ->
                            ErrorPage.update
                                -- TODO pass in url or no?
                                --{ data = thisPageData
                                --, sharedData = sharedData
                                --, routeParams = {}
                                --, path = justPage.path
                                --}
                                thisPageData
                                msg_
                                pageModel
                                --model.global -- TODO pass in Shared.Model
                                |> Tuple.mapBoth ModelErrorPage____ (Effect.map MsgErrorPage____)

                        _ ->
                            ( model.page, Effect.none )
            in
            ( { model | page = updatedPageModel }
            , pageCmd
            )


        MsgGlobal msg_ ->
            let
                ( sharedModel, globalCmd ) =
                    Shared.template.update msg_ model.global
            in
            ( { model | global = sharedModel }
            , globalCmd |> Effect.map MsgGlobal
            )

        OnPageChange record ->
            (init (Just model.global) Pages.Flags.PreRenderFlags sharedData pageData Nothing navigationKey <|
                Just
                    { path =
                        { path = record.path
                        , query = record.query
                        , fragment = record.fragment
                        }
                    , metadata = record.metadata
                    , pageUrl =
                        Just
                            { protocol = record.protocol
                            , host = record.host
                            , port_ = record.port_
                            , path = record.path
                            , query = record.query |> Maybe.map QueryParams.fromString
                            , fragment = record.fragment
                            }
                    }
            )
                |> (\\( updatedModel, cmd ) ->
                        case Shared.template.onPageChange of
                            Nothing ->
                                ( updatedModel, cmd )

                            Just thingy ->
                                let
                                    ( updatedGlobalModel, globalCmd ) =
                                        Shared.template.update
                                            (thingy
                                                { path = record.path
                                                , query = record.query
                                                , fragment = record.fragment
                                                }
                                            )
                                            model.global
                                in
                                ( { updatedModel
                                    | global = updatedGlobalModel
                                  }
                                , Effect.batch [ cmd, Effect.map MsgGlobal globalCmd ]
                                )
                   )


        ${templates
          .map(
            (name) => `
        Msg${pathNormalizedName(name)} msg_ ->
            let
                ( updatedPageModel, pageCmd, ( newGlobalModel, newGlobalCmd ) ) =
                    case ( model.page, pageData, Maybe.map3 (\\a b c -> ( a, b, c )) (model.current |> Maybe.andThen .metadata) (model.current |> Maybe.andThen .pageUrl) (model.current |> Maybe.map .path) ) of
                        ( Model${pathNormalizedName(
                          name
                        )} pageModel, Data${pathNormalizedName(
              name
            )} thisPageData, Just ( ${routeHelpers.destructureRoute(
              name,
              "routeParams"
            )}, pageUrl, justPage ) ) ->
                            Route.${moduleName(name)}.route.update
                                pageUrl
                                { data = thisPageData
                                , sharedData = sharedData
                                , action = Nothing
                                , routeParams = ${routeHelpers.referenceRouteParams(
                                  name,
                                  "routeParams"
                                )}
                                , path = justPage.path
                                , submit = Pages.Fetcher.submit Route.${moduleName(
                                  name
                                )}.w3_decode_ActionData
                                , transition = transition
                                , fetchers = fetchers
                                , pageFormState = pageFormState
                                }
                                msg_
                                pageModel
                                model.global
                                |> mapBoth Model${pathNormalizedName(
                                  name
                                )} (Effect.map Msg${pathNormalizedName(name)})
                                |> (\\( a, b, c ) ->
                                        case c of
                                            Just sharedMsg ->
                                                ( a, b, Shared.template.update sharedMsg model.global )

                                            Nothing ->
                                                ( a, b, ( model.global, Effect.none ) )
                                   )

                        _ ->
                            ( model.page, Effect.none, ( model.global, Effect.none ) )
            in
            ( { model | page = updatedPageModel, global = newGlobalModel }
            , Effect.batch [ pageCmd, newGlobalCmd |> Effect.map MsgGlobal ]
            )
`
          )
          .join("\n        ")}


templateSubscriptions : Maybe Route -> Path -> Model -> Sub Msg
templateSubscriptions route path model =
    case ( model.page, route ) of
        ${templates
          .map(
            (name) => `
        ( Model${pathNormalizedName(
          name
        )} templateModel, Just ${routeHelpers.destructureRoute(
              name,
              "routeParams"
            )} ) ->
            Route.${moduleName(name)}.route.subscriptions
                Nothing -- TODO wire through value
                ${routeHelpers.referenceRouteParams(name, "routeParams")}
                path
                templateModel
                model.global
                |> Sub.map Msg${pathNormalizedName(name)}
`
          )
          .join("\n        ")}


        _ ->
            Sub.none


main : ${
      phase === "browser"
        ? "Pages.Internal.Platform.Program Model Msg PageData ActionData Shared.Data ErrorPage"
        : "Pages.Internal.Platform.Cli.Program (Maybe Route)"
    }
main =
    ${
      phase === "browser"
        ? "Pages.Internal.Platform.application"
        : "Pages.Internal.Platform.Cli.cliApplication"
    } config

config : Pages.ProgramConfig.ProgramConfig Msg Model (Maybe Route) PageData ActionData Shared.Data (Effect Msg) mappedMsg ErrorPage
config =
        { init = init Nothing
        , urlToRoute = Route.urlToRoute
        , routeToPath = \\route -> route |> Maybe.map Route.routeToPath |> Maybe.withDefault []
        , site = ${phase === "browser" ? `Nothing` : `Just Site.config`}
        , globalHeadTags = ${
          phase === "browser" ? `Nothing` : `Just globalHeadTags`
        }
        , getStaticRoutes = ${
          phase === "browser"
            ? `DataSource.succeed []`
            : `getStaticRoutes |> DataSource.map (List.map Just)`
        }
        , handleRoute = handleRoute
        , view = view
        , update = update
        , subscriptions =
            \\route path model ->
                Sub.batch
                    [ Shared.template.subscriptions path model.global |> Sub.map MsgGlobal
                    , templateSubscriptions route path model
                    ]
        , onPageChange = OnPageChange
        , toJsPort = toJsPort
        , fromJsPort = fromJsPort identity
        , gotBatchSub = ${
          phase === "browser" ? "Sub.none" : "gotBatchSub identity"
        }
        , data = dataForRoute
        , action = action
        , onActionData = onActionData
        , sharedData = Shared.template.data
        , apiRoutes = ${
          phase === "browser"
            ? `\\_ -> []`
            : `\\htmlToString -> pathsToGenerateHandler :: routePatterns :: apiPatterns :: Api.routes getStaticRoutes htmlToString`
        }
        , pathPatterns = routePatterns3
        , basePath = [ ${basePath
          .split("/")
          .filter((segment) => segment !== "")
          .map((segment) => `"${segment}"`)
          .join(", ")} ]
        , sendPageData = sendPageData
        , byteEncodePageData = byteEncodePageData
        , byteDecodePageData = byteDecodePageData
        , hotReloadData = hotReloadData identity
        , encodeResponse = encodeResponse
        , decodeResponse = decodeResponse
        , encodeAction = encodeActionData
        , cmdToEffect = Effect.fromCmd
        , perform = Effect.perform
        , errorStatusCode = ErrorPage.statusCode
        , notFoundPage = ErrorPage.notFound
        , internalError = ErrorPage.internalError
        , errorPageToData = DataErrorPage____
        , notFoundRoute = Nothing
        }

onActionData actionData =
    case actionData of
${templates
  .map(
    (name) => `        ActionData${pathNormalizedName(name)} thisActionData ->
            Route.${name.join(
              "."
            )}.route.onAction |> Maybe.map (\\onAction -> onAction thisActionData) |> Maybe.map Msg${pathNormalizedName(
      name
    )}

`
  )
  .join("\n")}



globalHeadTags : DataSource (List Head.Tag)
globalHeadTags =
    (Site.config.head
        :: (Api.routes getStaticRoutes HtmlPrinter.htmlToString
                |> List.filterMap ApiRoute.getGlobalHeadTagsDataSource
           )
    )
        |> DataSource.combine
        |> DataSource.map List.concat


encodeResponse : ResponseSketch PageData ActionData Shared.Data -> Bytes.Encode.Encoder
encodeResponse =
    Pages.Internal.ResponseSketch.w3_encode_ResponseSketch w3_encode_PageData w3_encode_ActionData Shared.w3_encode_Data


decodeResponse : Bytes.Decode.Decoder (ResponseSketch PageData ActionData Shared.Data)
decodeResponse =
    Pages.Internal.ResponseSketch.w3_decode_ResponseSketch w3_decode_PageData w3_decode_ActionData Shared.w3_decode_Data


port hotReloadData : (Bytes -> msg) -> Sub msg


byteEncodePageData : PageData -> Bytes.Encode.Encoder
byteEncodePageData pageData =
    case pageData of
        DataErrorPage____ thisPageData ->
            ErrorPage.w3_encode_ErrorPage thisPageData


        Data404NotFoundPage____ ->
            Bytes.Encode.unsignedInt8 0

${templates
  .map(
    (name) => `        Data${pathNormalizedName(name)} thisPageData ->
            Route.${name.join(".")}.w3_encode_Data thisPageData
`
  )
  .join("\n")}

encodeActionData : ActionData -> Bytes.Encode.Encoder
encodeActionData actionData =
    case actionData of
${templates
  .map(
    (name) => `        ActionData${pathNormalizedName(name)} thisActionData ->
            Route.${name.join(".")}.w3_encode_ActionData thisActionData
`
  )
  .join("\n")}


port sendPageData : Pages.Internal.Platform.ToJsPayload.NewThingForPort -> Cmd msg


byteDecodePageData : Maybe Route -> Bytes.Decode.Decoder PageData
byteDecodePageData route =
    case route of
        Nothing -> Bytes.Decode.fail
${templates
  .map(
    (name) =>
      `        (Just ${
        emptyRouteParams(name)
          ? `Route.${routeHelpers.routeVariant(name)}`
          : `(Route.${routeHelpers.routeVariant(name)} _)`
      }) ->\n            Route.${name.join(
        "."
      )}.w3_decode_Data |> Bytes.Decode.map Data${routeHelpers.routeVariant(
        name
      )}
`
  )
  .join("\n")}




dataForRoute : Maybe Route -> DataSource (Server.Response.Response PageData ErrorPage)
dataForRoute route =
    case route of
        Nothing ->
            DataSource.succeed (Server.Response.render Data404NotFoundPage____ |> Server.Response.withStatusCode 404 |> Server.Response.mapError never )

        ${templates
          .map(
            (name) =>
              `Just ${
                emptyRouteParams(name)
                  ? `Route.${routeHelpers.routeVariant(name)}`
                  : `(Route.${routeHelpers.routeVariant(name)} routeParams)`
              } ->\n            Route.${name.join(
                "."
              )}.route.data ${routeHelpers.referenceRouteParams(
                name,
                "routeParams"
              )} 
                 |> DataSource.map (Server.Response.map Data${routeHelpers.routeVariant(
                   name
                 )})
              `
          )
          .join("\n        ")}

action : Maybe Route -> DataSource (Server.Response.Response ActionData ErrorPage)
action route =
    case route of
        Nothing ->
            DataSource.succeed ( Server.Response.plainText "TODO" )

        ${templates
          .map(
            (name) =>
              `Just ${
                emptyRouteParams(name)
                  ? `Route.${routeHelpers.routeVariant(name)}`
                  : `(Route.${routeHelpers.routeVariant(name)} routeParams)`
              } ->\n            Route.${name.join(
                "."
              )}.route.action ${routeHelpers.referenceRouteParams(
                name,
                "routeParams"
              )} 
                 |> DataSource.map (Server.Response.map ActionData${routeHelpers.routeVariant(
                   name
                 )})
              `
          )
          .join("\n        ")}



handleRoute : Maybe Route -> DataSource (Maybe Pages.Internal.NotFoundReason.NotFoundReason)
handleRoute maybeRoute =
    case maybeRoute of
        Nothing ->
            DataSource.succeed Nothing

        ${templates
          .map(
            (name) =>
              `Just (Route.${routeHelpers.routeVariant(name)}${
                routeHelpers.parseRouteParams(name).length === 0
                  ? ""
                  : " routeParams"
              }) ->\n            Route.${name.join(
                "."
              )}.route.handleRoute { moduleName = [ ${name
                .map((part) => `"${part}"`)
                .join(", ")} ], routePattern = ${routeHelpers.toElmPathPattern(
                name
              )} } (\\param -> [ ${routeHelpers
                .parseRouteParams(name)
                .map(
                  (param) =>
                    `( "${param.name}", ${paramAsElmString(param)} param.${
                      param.name
                    } )`
                )
                .join(", ")} ]) ${routeHelpers.referenceRouteParams(
                name,
                "routeParams"
              )}`
          )
          .join("\n        ")}


stringToString : String -> String
stringToString string =
    "\\"" ++ string ++ "\\""


nonEmptyToString : ( String, List String ) -> String
nonEmptyToString ( first, rest ) =
    "( "
        ++ stringToString first
        ++ ", [ "
        ++ (rest
                |> List.map stringToString
                |> String.join ", "
           )
        ++ " ] )"


listToString : List String -> String
listToString strings =
    "[ "
        ++ (strings
                |> List.map stringToString
                |> String.join ", "
           )
        ++ " ]"


maybeToString : Maybe String -> String
maybeToString maybeString =
    case maybeString of
        Just string ->
            "Just " ++ stringToString string

        Nothing ->
            "Nothing"




routePatterns : ApiRoute.ApiRoute ApiRoute.Response
routePatterns =
    ApiRoute.succeed
        (Json.Encode.list
            (\\{ kind, pathPattern } ->
                Json.Encode.object
                    [ ( "kind", Json.Encode.string kind )
                    , ( "pathPattern", Json.Encode.string pathPattern )
                    ]
            )
            [ ${sortTemplates(templates)
              .flatMap((name) => {
                let patterns = routeHelpers.toPathPatterns(name);
                return patterns.map(
                  (pattern) =>
                    `{ kind = Route.${moduleName(
                      name
                    )}.route.kind, pathPattern = "${pattern}" }`
                );
              })
              .join("\n            , ")}
          
            ]
            |> (\\json -> DataSource.succeed ( Json.Encode.encode 0 json ))
        )
        |> ApiRoute.literal "route-patterns.json"
        |> ApiRoute.single

apiPatterns : ApiRoute.ApiRoute ApiRoute.Response
apiPatterns =
    let
        apiPatternsString =
            Api.routes getStaticRoutes (\\_ -> "")
                |> List.map ApiRoute.toJson

    in
    ApiRoute.succeed
        (Json.Encode.list identity apiPatternsString
            |> (\\json -> DataSource.succeed ( Json.Encode.encode 0 json ))
        )
        |> ApiRoute.literal "api-patterns.json"
        |> ApiRoute.single


routePatterns2 : List String
routePatterns2 =
    [ ${sortTemplates(templates)
      .map((name) => {
        return `"${routeHelpers.toPathPattern(name)}"`;
      })
      .join("\n    , ")}
    ]


routePatterns3 : List Pages.Internal.RoutePattern.RoutePattern
routePatterns3 =
    [ ${sortTemplates(templates)
      .map((name) => {
        return `${routeHelpers.toElmPathPattern(name)}`;
      })
      .join("\n    , ")}
    ]

getStaticRoutes : DataSource (List Route)
getStaticRoutes =
    DataSource.combine
        [ ${templates
          .map((name) => {
            return `Route.${moduleName(
              name
            )}.route.staticRoutes |> DataSource.map (List.map ${
              emptyRouteParams(name)
                ? `(\\_ -> Route.${pathNormalizedName(name)}))`
                : `Route.${pathNormalizedName(name)})`
            }`;
          })
          .join("\n        , ")}
        ]
        |> DataSource.map List.concat


pathsToGenerateHandler : ApiRoute.ApiRoute ApiRoute.Response
pathsToGenerateHandler =
    ApiRoute.succeed
        (DataSource.map2
            (\\pageRoutes apiRoutes ->
                (pageRoutes ++ (apiRoutes |> List.map (\\api -> "/" ++ api)))
                    |> Json.Encode.list Json.Encode.string
                    |> Json.Encode.encode 0
            )
            (DataSource.map
                (List.map
                    (\\route ->
                        route
                            |> Route.toPath
                            |> Path.toAbsolute
                    )
                )
                getStaticRoutes
            )
            ((routePatterns :: apiPatterns :: Api.routes getStaticRoutes (\\_ -> ""))
                |> List.map ApiRoute.getBuildTimeRoutes
                |> DataSource.combine
                |> DataSource.map List.concat
            )
        )
        |> ApiRoute.literal "all-paths.json"
        |> ApiRoute.single


port toJsPort : Json.Encode.Value -> Cmd msg

port fromJsPort : (Json.Decode.Value -> msg) -> Sub msg

port gotBatchSub : (Json.Decode.Value -> msg) -> Sub msg


mapBoth : (a -> b) -> (c -> d) -> ( a, c, e ) -> ( b, d, e )
mapBoth fnA fnB ( a, b, c ) =
    ( fnA a, fnB b, c )

encodeBytes : (b -> Bytes.Encode.Encoder) -> b -> Bytes
encodeBytes bytesEncoder items =
    Bytes.Encode.encode (bytesEncoder items)


decodeBytes : Bytes.Decode.Decoder a -> Bytes -> Result String a
decodeBytes bytesDecoder items =
    Bytes.Decode.decode bytesDecoder items
    -- Lamdera.Wire3.bytesDecodeStrict bytesDecoder items
        |> Result.fromMaybe "Decoding error"
`,
    routesModule: `module Route exposing (baseUrlAsPath, Route(..), link, matchers, routeToPath, toLink, urlToRoute, toPath, redirectTo, toString)

{-|

@docs Route, link, matchers, routeToPath, toLink, urlToRoute, toPath, redirectTo, toString, baseUrlAsPath

-}


import Server.Response
import Html exposing (Attribute, Html)
import Html.Attributes as Attr
import Path exposing (Path)
import Pages.Internal.Router
import Pattern


{-| -}
type Route
    = ${templates.map(routeHelpers.routeVariantDefinition).join("\n    | ")}


{-| -}
urlToRoute : { url | path : String } -> Maybe Route
urlToRoute url =
    url.path
    |> withoutBaseUrl 
    |> Pages.Internal.Router.firstMatch matchers


baseUrl : String
baseUrl =
    "${basePath}"


{-| -}
baseUrlAsPath : List String
baseUrlAsPath =
    baseUrl
    |> String.split "/"
    |> List.filter (not << String.isEmpty)


withoutBaseUrl path =
    if (path |> String.startsWith baseUrl) then
      String.dropLeft (String.length baseUrl) path
    else
      path

{-| -}
matchers : List (Pages.Internal.Router.Matcher Route)
matchers =
    [ ${sortTemplates(templates)
      .map(
        (name) => `{ pattern = "^${routeRegex(name).pattern}$"
      , toRoute = ${routeRegex(name).toRoute}
     }\n`
      )
      .join("    , ")}
    ]


{-| -}
routeToPath : Route -> List String
routeToPath route =
    case route of
        ${templates
          .map(
            (name) =>
              `${routeHelpers.routeVariant(name)}${
                routeHelpers.parseRouteParams(name).length === 0
                  ? ""
                  : ` params`
              } ->\n           List.concat [ ${routeHelpers
                .parseRouteParamsWithStatic(name)
                .map((param) => {
                  switch (param.kind) {
                    case "static": {
                      return param.name === "Index"
                        ? `[]`
                        : `[ "${camelToKebab(param.name)}" ]`;
                    }
                    case "optional": {
                      return `Pages.Internal.Router.maybeToList params.${param.name}`;
                    }
                    case "required-splat": {
                      return `Pages.Internal.Router.nonEmptyToList params.${param.name}`;
                    }
                    case "dynamic": {
                      return `[ params.${param.name} ]`;
                    }
                    case "optional-splat": {
                      return `params.${param.name}`;
                    }
                  }
                })} ]`
          )
          .join("\n        ")}

{-| -}
toPath : Route -> Path
toPath route =
    (baseUrlAsPath ++ (route |> routeToPath)) |> String.join "/" |> Path.fromString


{-| -}
toString : Route -> String
toString route =
    route |> toPath |> Path.toAbsolute


{-| -}
toLink : (List (Attribute msg) -> tag) -> Route -> tag
toLink toAnchorTag route =
    toAnchorTag
        [ route |> toString |> Attr.href
        , Attr.attribute "elm-pages:prefetch" ""
        ]


{-| -}
link : List (Attribute msg) -> List (Html msg) -> Route -> Html msg
link attributes children route =
    toLink
        (\\anchorAttrs ->
            Html.a
                (anchorAttrs ++ attributes)
                children
        )
        route


{-| -}
redirectTo : Route -> Server.Response.Response data error
redirectTo route =
    route
        |> toString
        |> Server.Response.temporaryRedirect
`,
    fetcherModules: templates.map((name) => {
      return [name, fetcherModule(name)];
    }),
  };
}

function emptyRouteParams(name) {
  return routeHelpers.parseRouteParams(name).length === 0;
}

/**
 * @param {string} segment
 * @returns {'static' | 'dynamic' | 'optional' | 'index' | 'required-splat' | 'optional-splat'}
 */
function segmentKind(segment) {
  if (segment === "Index") {
    return "index";
  }
  const routeParamMatch = segment.match(/([A-Z][A-Za-z0-9]*)(_?_?)$/);
  const segmentKind = (routeParamMatch && routeParamMatch[2]) || "";
  const isSplat = routeParamMatch && routeParamMatch[1] === "SPLAT";
  if (segmentKind === "") {
    return "static";
  } else if (segmentKind === "_") {
    return isSplat ? "required-splat" : "dynamic";
  } else if (segmentKind === "__") {
    return isSplat ? "optional-splat" : "optional";
  } else {
    throw "Unhandled segmentKind";
  }
}

/**
 *
 * @param {string[][]} templates
 * @returns
 */
function sortTemplates(templates) {
  return templates.sort((first, second) => {
    const a = sortScore(first);
    const b = sortScore(second);
    if (b.splatScore === a.splatScore) {
      if (b.staticSegments === a.staticSegments) {
        return b.dynamicSegments - a.dynamicSegments;
      } else {
        return b.staticSegments - a.staticSegments;
      }
    } else {
      return a.splatScore - b.splatScore;
    }
  });
}

/**
 * @param {string[]} name
 */
function sortScore(name) {
  const parsedParams = routeHelpers.parseRouteParamsWithStatic(name);
  return parsedParams.reduce(
    (currentScore, segment) => {
      switch (segment.kind) {
        case "dynamic": {
          return {
            ...currentScore,
            dynamicSegments: currentScore.dynamicSegments + 1,
          };
        }
        case "static": {
          return {
            ...currentScore,
            staticSegments: currentScore.staticSegments + 1,
          };
        }
        case "optional": {
          return {
            ...currentScore,
            splatScore: 10,
          };
        }
        case "required-splat": {
          return {
            ...currentScore,
            splatScore: 100,
          };
        }
        case "optional-splat": {
          return {
            ...currentScore,
            splatScore: 100,
          };
        }
      }
    },
    { staticSegments: 0, dynamicSegments: 0, splatScore: 0 }
  );
}

/**
 * @param {string[]} name
 */
function routeRegex(name) {
  const parsedParams = routeHelpers.parseRouteParams(name);
  const includesOptional = parsedParams.some(
    (param) => param.kind === "optional"
  );
  const params = routeHelpers.routeParams(name);
  const parserCode = name
    .flatMap((section) => {
      const routeParamMatch = section.match(/([A-Z][A-Za-z0-9]*)(_?_?)$/);
      const maybeParam = routeParamMatch && routeParamMatch[1];
      switch (segmentKind(section)) {
        case "static": {
          return [`\\\\/` + camelToKebab(section)];
        }
        case "index": {
          return [`\\\\/`];
        }
        case "dynamic": {
          return [`\\\\/(?:([^/]+))`];
        }
        case "required-splat": {
          return [`\\\\/(.*)`];
        }
        case "optional-splat": {
          return [`(.*)`];
        }
        case "optional": {
          return [`\\\\/(?:([^/]+))?`];
        }
      }
    })
    .join("");

  const toRoute = `\\matches ->
      case matches of
          [ ${parsedParams
            .flatMap((parsedParam) => {
              switch (parsedParam.kind) {
                case "optional": {
                  return parsedParam.name;
                }
                case "dynamic": {
                  return `Just ${parsedParam.name}`;
                }
                case "required-splat": {
                  return `Just splat`;
                }
                case "optional-splat": {
                  return `splat`;
                }
              }
            })
            .join(", ")} ] ->
              Just ${
                parsedParams.length === 0
                  ? pathNormalizedName(name)
                  : `( ${pathNormalizedName(name)} { ${parsedParams.map(
                      (param) => {
                        return `${param.name} = ${prefixThing(param)}${
                          param.name
                        }`;
                      }
                    )} } )`
              }
          _ ->
              Nothing

  `;

  return { pattern: parserCode, toRoute };
}

function prefixThing(param) {
  switch (param.kind) {
    case "optional-splat": {
      return "Pages.Internal.Router.fromOptionalSplat ";
    }
    case "required-splat": {
      return "Pages.Internal.Router.toNonEmpty ";
    }
    default: {
      return "";
    }
  }
}

function fetcherModule(name) {
  let moduleName = name.join(".");
  // TODO need to account for splat routes/etc.
  let modulePath = name.join("/");
  let fetcherPath = routeHelpers
    .parseRouteParamsWithStatic(name)
    .map((param) => {
      switch (param.kind) {
        case "static": {
          return param.name === "Index"
            ? `[]`
            : `[ "${camelToKebab(param.name)}" ]`;
        }
        case "optional": {
          return `Pages.Internal.Router.maybeToList params.${param.name}`;
        }
        case "required-splat": {
          return `Pages.Internal.Router.nonEmptyToList params.${param.name}`;
        }
        case "dynamic": {
          return `[ params.${param.name} ]`;
        }
        case "optional-splat": {
          return `params.${param.name}`;
        }
      }
    })
    .join(", ");

  return `module Fetcher.${moduleName} exposing (submit)

{-| -}

import Bytes exposing (Bytes)
import Bytes.Decode
import FormDecoder
import Http
import Pages.Fetcher
import Route.${moduleName}


submit :
    (Result Http.Error Route.${moduleName}.ActionData -> msg)
    ->
        { fields : List ( String, String )
        , headers : List ( String, String )
        }
    -> Pages.Fetcher.Fetcher msg
submit toMsg options =
    { decoder =
        \\bytesResult ->
            bytesResult
                |> Result.andThen
                    (\\okBytes ->
                        okBytes
                            |> Bytes.Decode.decode Route.${moduleName}.w3_decode_ActionData
                            |> Result.fromMaybe (Http.BadBody "Couldn't decode bytes.")
                    )
                |> toMsg
    , fields = options.fields
    , headers = ("elm-pages-action-only", "true") :: options.headers
        , url = ${
          fetcherPath === ""
            ? 'Just "/content.dat"'
            : `[ ${fetcherPath}, [ "content.dat" ] ] |> List.concat |> String.join "/" |> Just`
        }
    }
    |> Pages.Fetcher.Fetcher
`;
}

/**
 * @param {string[]} name
 */
function routePathList(name) {
  return withoutTrailingIndex(name)
    .map((section) => {
      const routeParamMatch = section.match(/([A-Z][A-Za-z0-9]*)_$/);
      const maybeParam = routeParamMatch && routeParamMatch[1];
      if (maybeParam) {
        return `params.${maybeParam.toLowerCase()}`;
      } else {
        return `"${camelToKebab(section)}"`;
      }
    })
    .join(", ");
}

/**
 * @param {string[]} name
 */
function withoutTrailingIndex(name) {
  if (name[name.length - 1] === "Index") {
    return name.slice(0, -1);
  } else {
    return name;
  }
}
/**
 * Convert Strings from camelCase to kebab-case
 * @param {string} input
 * @returns {string}
 */
function camelToKebab(input) {
  return input.replace(/([a-z])([A-Z])/g, "$1-$2").toLowerCase();
}
/**
 * @param {string[]} name
 */
function isParameterizedRoute(name) {
  return name.some((section) => section.includes("_"));
}

/**
 * @param {string[]} name
 */
function pathNormalizedName(name) {
  return name.join("__");
}

/**
 * @param {string[]} name
 */
function moduleName(name) {
  return name.join(".");
}

function paramAsElmString(param) {
  switch (param.kind) {
    case "dynamic": {
      return "stringToString";
    }
    case "optional": {
      return "maybeToString";
    }
    case "required-splat": {
      return "nonEmptyToString";
    }
    case "optional-splat": {
      return "listToString";
    }
  }
}

module.exports = { generateTemplateModuleConnector, sortTemplates };
