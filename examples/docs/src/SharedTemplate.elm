module SharedTemplate exposing (..)

import Document exposing (Document)
import Html exposing (Html)
import Pages.PagePath exposing (PagePath)
import Pages.StaticHttp as StaticHttp


type alias SharedTemplate sharedMsg sharedModel sharedStaticData route templateDemuxMsg msg1 msg2 =
    { init :
        Maybe
            { path :
                { path : PagePath
                , query : Maybe String
                , fragment : Maybe String
                }
            , metadata : route
            }
        -> ( sharedModel, Cmd sharedMsg )
    , update : sharedMsg -> sharedModel -> ( sharedModel, Cmd sharedMsg )
    , view :
        sharedStaticData
        ->
            { path : PagePath
            , frontmatter : route
            }
        -> sharedModel
        -> (sharedMsg -> templateDemuxMsg)
        -> Document templateDemuxMsg
        -> { body : Html templateDemuxMsg, title : String }
    , map : (msg1 -> msg2) -> Document msg1 -> Document msg2
    , staticData : StaticHttp.Request sharedStaticData
    , subscriptions : PagePath -> sharedModel -> Sub sharedMsg
    , onPageChange :
        Maybe
            ({ path : PagePath
             , query : Maybe String
             , fragment : Maybe String
             }
             -> sharedMsg
            )
    }
