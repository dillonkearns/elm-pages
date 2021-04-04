module StaticResponsesTests exposing (all)

import Dict
import Expect
import Pages.Internal.Platform.Mode as Mode
import Pages.Internal.Platform.StaticResponses as StaticResponses
import Pages.Internal.Platform.ToJsPayload as ToJsPayload
import Pages.StaticHttp as StaticHttp
import SecretsDict
import Test exposing (Test, describe, test)


all : Test
all =
    describe "Static Http Responses"
        [--test "andThen" <|
         --    \() ->
         --        StaticResponses.init config []
         --            |> StaticResponses.nextStep config Mode.Dev (SecretsDict.unmasked Dict.empty) Dict.empty []
         --            |> Expect.equal
         --                (StaticResponses.Finish
         --                    (ToJsPayload.Success
         --                        { errors = []
         --                        , filesToGenerate = []
         --                        , manifest = ToJsPayload.stubManifest
         --                        , pages = Dict.fromList []
         --                        , staticHttpCache = Dict.fromList []
         --                        }
         --                    )
         --                )
        ]


config =
    { generateFiles = StaticHttp.succeed []
    , manifest = ToJsPayload.stubManifest
    , view = \_ _ -> StaticHttp.succeed ()
    , getStaticRoutes = StaticHttp.succeed []
    , routeToPath = \_ -> []
    , pathKey = ()
    }
