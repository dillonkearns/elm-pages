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
    describe "Static Http Requests"
        [ test "andThen" <|
            \() ->
                StaticResponses.init Dict.empty (Ok []) config []
                    |> StaticResponses.nextStep config (Ok []) (Ok []) Mode.Dev (SecretsDict.unmasked Dict.empty) Dict.empty []
                    |> Expect.equal
                        (StaticResponses.Finish
                            (ToJsPayload.Success
                                { errors = []
                                , filesToGenerate = []
                                , manifest = ToJsPayload.stubManifest
                                , pages = Dict.fromList []
                                , staticHttpCache = Dict.fromList []
                                }
                            )
                        )
        ]


config =
    { generateFiles = \_ -> StaticHttp.succeed []
    , content = []
    , manifest = ToJsPayload.stubManifest
    }
