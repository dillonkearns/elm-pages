const fs = require("fs");
const globby = require("globby");
const path = require("path");

async function generateTemplateModuleConnector() {
  fs.copyFileSync(
    path.join(__dirname, `./Template.elm`),
    `./elm-stuff/elm-pages/Template.elm`
  );
  const templates = globby
    .sync(["src/Template/*.elm"], {})
    .map((file) => path.basename(file, ".elm"));
  let wildcardForMoreThanOne = (indentation, wildcardBody) =>
    templates.length > 1
      ? `${indentation}_ ->\n${indentation}    ${wildcardBody}`
      : ``;

  /** @type {[string, boolean][]} */
  const templatesAndState = await templatesWithLocalState(templates);
  // console.log("templatesAndState", templatesAndState);

  return `module TemplateModulesBeta exposing (..)

import Browser
import Pages.Manifest as Manifest
import Shared
import TemplateType as M exposing (TemplateType)
import Head
import Html exposing (Html)
import Pages
import Pages.PagePath exposing (PagePath)
import Pages.Platform
import Pages.StaticHttp as StaticHttp
${templatesAndState
  .map(([name, hasLocalState]) => `import Template.${name}`)
  .join("\n")}


type alias Model =
    { global : Shared.Model
    , page : TemplateModel
    , current :
        Maybe
            { path :
                { path : PagePath Pages.PathKey
                , query : Maybe String
                , fragment : Maybe String
                }
            , metadata : TemplateType
            }
    }


type TemplateModel
    = ${templatesAndState
      .map(([name, hasLocalState]) => `Model${name} Template.${name}.Model\n`)
      .join("    | ")}
    | NotFound



type Msg
    = MsgGlobal Shared.Msg
    | OnPageChange
        { path : PagePath Pages.PathKey
        , query : Maybe String
        , fragment : Maybe String
        , metadata : TemplateType
        }
    | ${templatesAndState
      .map(([name, hasLocalState]) => `Msg${name} Template.${name}.Msg\n`)
      .join("    | ")}


view :
    List ( PagePath Pages.PathKey, TemplateType )
    ->
        { path : PagePath Pages.PathKey
        , frontmatter : TemplateType
        }
    ->
        StaticHttp.Request
            { view : Model -> Shared.RenderedBody -> { title : String, body : Html Msg }
            , head : List (Head.Tag Pages.PathKey)
            }
view siteMetadata page =
    case page.frontmatter of
        ${templatesAndState
          .map(
            ([name, hasLocalState]) =>
              `M.${name} metadata ->
            StaticHttp.map2
                (\\data globalData ->
                    { view =
                        \\model rendered ->
                            case model.page of
                                Model${name} subModel ->
                                    Template.${name}.template.view
                                        subModel
                                        model.global
                                        siteMetadata
                                        { static = data
                                        , sharedStatic = globalData
                                        , metadata = metadata
                                        , path = page.path
                                        }
                                        rendered
                                        |> (\\{ title, body } ->
                                                Shared.template.view
                                                    globalData
                                                    page
                                                    model.global
                                                    MsgGlobal
                                                    ({ title = title, body = body }
                                                        |> Shared.template.map Msg${name}
                                                    )
                                           )

                                NotFound ->
                                    { title = "", body = Html.text "" }

${wildcardForMoreThanOne(
  "                                ",
  '{ title = "", body = Html.text "" }'
)}
                    , head = Template.${name}.template.head
                        { static = data
                        , sharedStatic = globalData
                        , metadata = metadata
                        , path = page.path
                        }
                    }
                )
                (Template.${name}.template.staticData siteMetadata)
                (Shared.template.staticData siteMetadata)
`
          )
          .join("\n\n        ")}


init :
    Maybe Shared.Model
    ->
        Maybe
            { path :
                { path : PagePath Pages.PathKey
                , query : Maybe String
                , fragment : Maybe String
                }
            , metadata : TemplateType
            }
    -> ( Model, Cmd Msg )
init currentGlobalModel maybePagePath =
    let
        ( sharedModel, globalCmd ) =
            currentGlobalModel |> Maybe.map (\\m -> ( m, Cmd.none )) |> Maybe.withDefault (Shared.template.init maybePagePath)

        ( templateModel, templateCmd ) =
            case maybePagePath |> Maybe.map .metadata of
                Nothing ->
                    ( NotFound, Cmd.none )

                Just meta ->
                    case meta of
                        ${templatesAndState
                          .map(
                            ([name, hasLocalState]) => `M.${name} metadata ->
                            Template.${name}.template.init metadata
                                |> Tuple.mapBoth Model${name} (Cmd.map Msg${name})

`
                          )
                          .join("\n                        ")}
    in
    ( { global = sharedModel
      , page = templateModel
      , current = maybePagePath
      }
    , Cmd.batch
        [ templateCmd
        , globalCmd |> Cmd.map MsgGlobal
        ]
    )



update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        MsgGlobal msg_ ->
            let
                ( sharedModel, globalCmd ) =
                    Shared.template.update msg_ model.global
            in
            ( { model | global = sharedModel }
            , globalCmd |> Cmd.map MsgGlobal
            )

        OnPageChange record ->
            (init (Just model.global) <|
                Just
                    { path =
                        { path = record.path
                        , query = record.query
                        , fragment = record.fragment
                        }
                    , metadata = record.metadata
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
                                , Cmd.batch [ cmd, Cmd.map MsgGlobal globalCmd ]
                                )
                   )


        ${templatesAndState
          .map(
            ([name, hasLocalState]) => `
        Msg${name} msg_ ->
            let
                ( updatedPageModel, pageCmd, ( newGlobalModel, newGlobalCmd ) ) =
                    case ( model.page, model.current |> Maybe.map .metadata ) of
                        ( Model${name} pageModel, Just (M.${name} metadata) ) ->
                            Template.${name}.template.update
                                metadata
                                msg_
                                pageModel
                                model.global
                                |> mapBoth Model${name} (Cmd.map Msg${name})
                                |> (\\( a, b, c ) ->
                                        case c of
                                            Just sharedMsg ->
                                                ( a, b, Shared.template.update (Shared.SharedMsg sharedMsg) model.global )

                                            Nothing ->
                                                ( a, b, ( model.global, Cmd.none ) )
                                   )

                        _ ->
                            ( model.page, Cmd.none, ( model.global, Cmd.none ) )
            in
            ( { model | page = updatedPageModel, global = newGlobalModel }
            , Cmd.batch [ pageCmd, newGlobalCmd |> Cmd.map MsgGlobal ]
            )
`
          )
          .join("\n        ")}


type alias SiteConfig =
    { canonicalUrl : String
    , manifest : Manifest.Config Pages.PathKey
    }

templateSubscriptions : TemplateType -> PagePath Pages.PathKey -> Model -> Sub Msg
templateSubscriptions metadata path model =
    case model.page of
        ${templatesAndState
          .map(
            ([name, hasLocalState]) => `
        Model${name} templateModel ->
            case metadata of
                M.${name} templateMetadata ->
                    Template.${name}.template.subscriptions
                        templateMetadata
                        path
                        templateModel
                        model.global
                        |> Sub.map Msg${name}

${wildcardForMoreThanOne("                ", "Sub.none")}
`
          )
          .join("\n        ")}


        NotFound ->
            Sub.none


mainTemplate { documents, site } =
    Pages.Platform.init
        { init = init Nothing
        , view = view
        , update = update
        , subscriptions =
            \\metadata path model ->
                Sub.batch
                    [ Shared.template.subscriptions metadata path model.global |> Sub.map MsgGlobal
                    , templateSubscriptions metadata path model
                    ]
        , documents = documents
        , onPageChange = Just OnPageChange
        , manifest = site.manifest
        , canonicalSiteUrl = site.canonicalUrl
        , internals = Pages.internals
        }



mapDocument : Browser.Document Never -> Browser.Document mapped
mapDocument document =
    { title = document.title
    , body = document.body |> List.map (Html.map never)
    }


mapBoth fnA fnB ( a, b, c ) =
    ( fnA a, fnB b, c )
`;
}

async function templatesWithLocalState(templates) {
  return new Promise((resolve, reject) => {
    const { compileToStringSync } = require("../node-elm-compiler/index.js");
    fs.writeFileSync(
      `./elm-stuff/elm-pages/TemplatesAndState.elm`,
      hasLocalStateModule(templates)
    );
    const data = compileToStringSync(
      [`./elm-stuff/elm-pages/TemplatesAndState.elm`],
      {}
    );
    eval(data.toString());
    const app = Elm.TemplatesAndState.init({ flags: null });
    app.ports.toJs.subscribe(function (payload) {
      resolve(payload);
      //   console.log("@@@@ payload from Elm", payload);
    });
  });
}

function hasLocalStateModule(templates) {
  return `port module TemplatesAndState exposing (main)

import Template
${templates.map((template) => `import Template.${template}`).join("\n")}


port toJs : List ( String, Bool ) -> Cmd msg


main =
  Platform.worker
    { init = \\() -> ( (), toJs [ ${templates.map(
      (template) =>
        `( "${template}", Template.hasLocalState Template.${template}.template )`
    )} ] )
    , update = \\msg model -> (model, Cmd.none)
    , subscriptions = \\model -> Sub.none
    }`;
}
module.exports = { generateTemplateModuleConnector };
