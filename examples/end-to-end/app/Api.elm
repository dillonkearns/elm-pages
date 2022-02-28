module Api exposing (routes)

import ApiRoute exposing (ApiRoute)
import DataSource exposing (DataSource)
import DataSource.Glob as Glob exposing (Glob)
import DataSource.Internal.Glob
import Html exposing (Html)
import Json.Decode as Decode
import Result.Extra
import Route exposing (Route)
import Server.Request as Request
import Server.Response as Response


routes :
    DataSource (List Route)
    -> (Html Never -> String)
    -> List (ApiRoute.ApiRoute ApiRoute.Response)
routes getStaticRoutes htmlToString =
    [ greet
    , globTestRouteNew
    ]


greet : ApiRoute ApiRoute.Response
greet =
    ApiRoute.succeed
        (Request.oneOf
            [ Request.expectFormPost
                (\{ field, optionalField } ->
                    field "first"
                )
            , Request.expectJsonBody (Decode.field "first" Decode.string)
            , Request.expectQueryParam "first"
            , Request.expectMultiPartFormPost
                (\{ field, optionalField } ->
                    field "first"
                )
            ]
            |> Request.map
                (\firstName ->
                    Response.plainText ("Hello " ++ firstName)
                        |> DataSource.succeed
                )
        )
        |> ApiRoute.literal "api"
        |> ApiRoute.slash
        |> ApiRoute.literal "greet"
        |> ApiRoute.serverRender


globTestsNew : List (DataSource (Result String ()))
globTestsNew =
    [ test
        { name = "1"
        , glob = findBySplat []
        , expected = [ "content/index.md" ]
        }
    , test
        { name = "2"
        , glob = findBySplat [ "foo" ]
        , expected = [ "content/foo/index.md" ]
        }
    , test
        { name = "3"
        , glob = findBySplat [ "bar" ]
        , expected = [ "content/bar.md" ]
        }
    , test
        { name = "4"
        , glob =
            Glob.succeed identity
                |> Glob.match (Glob.literal "glob-test-cases/content1/")
                |> Glob.capture Glob.wildcard
                |> Glob.match (Glob.oneOf ( ( ".md", () ), [ ( "/", () ) ] ))
                |> Glob.match Glob.wildcard
        , expected = [ "about", "posts" ]
        }
    , test
        { name = "5"
        , glob =
            Glob.succeed
                (\first second wildcardPart ->
                    { first = first
                    , second = second
                    , wildcard = wildcardPart
                    }
                )
                |> Glob.capture (Glob.literal "glob-test-cases/")
                |> Glob.capture (Glob.literal "content1/")
                |> Glob.capture Glob.wildcard
        , expected =
            [ { first = "glob-test-cases/"
              , second = "content1/"
              , wildcard = "about.md"
              }
            ]
        }
    , test
        { name = "6"
        , glob =
            Glob.succeed Tuple.pair
                |> Glob.match (Glob.literal "glob-test-cases/")
                |> Glob.capture Glob.wildcard
                |> Glob.match (Glob.literal ".")
                |> Glob.capture
                    (Glob.oneOf
                        ( ( "yml", YAML )
                        , [ ( "json", JSON )
                          ]
                        )
                    )
        , expected = [ ( "data-file", JSON ) ]
        }
    , test
        { name = "7"
        , glob =
            Glob.succeed
                (\year month day slug ->
                    { year = year
                    , month = month
                    , day = day
                    , slug = slug
                    }
                )
                |> Glob.match (Glob.literal "glob-test-cases/")
                |> Glob.match (Glob.literal "archive/")
                |> Glob.capture Glob.int
                |> Glob.match (Glob.literal "/")
                |> Glob.capture Glob.int
                |> Glob.match (Glob.literal "/")
                |> Glob.capture Glob.int
                |> Glob.match (Glob.literal "/")
                |> Glob.capture Glob.wildcard
                |> Glob.match (Glob.literal ".md")
        , expected =
            [ { day = 10
              , month = 6
              , year = 1977
              , slug = "apple-2-released"
              }
            ]
        }
    , test
        { name = "8"
        , glob =
            Glob.succeed identity
                |> Glob.match (Glob.literal "glob-test-cases/at-least-one/")
                |> Glob.match Glob.wildcard
                |> Glob.match (Glob.literal ".")
                |> Glob.capture
                    (Glob.atLeastOne
                        ( ( "yml", YAML )
                        , [ ( "json", JSON )
                          ]
                        )
                    )
        , expected = [ ( JSON, [ YAML, JSON, JSON ] ) ]
        }
    ]


findBySplat : List String -> Glob String
findBySplat splat =
    if splat == [] then
        Glob.literal "content/index.md"

    else
        Glob.succeed identity
            |> Glob.captureFilePath
            |> Glob.match (Glob.literal "content/")
            |> Glob.match (Glob.literal (String.join "/" splat))
            |> Glob.match
                (Glob.oneOf
                    ( ( "", () )
                    , [ ( "/index", () ) ]
                    )
                )
            |> Glob.match (Glob.literal ".md")


test : { name : String, glob : Glob value, expected : List value } -> DataSource (Result String ())
test { glob, name, expected } =
    Glob.toDataSource glob
        |> DataSource.map
            (\actual ->
                if actual == expected then
                    Ok ()

                else
                    Err <|
                        name
                            ++ " failed\nPattern: `"
                            ++ DataSource.Internal.Glob.toPattern glob
                            ++ "`\nExpected\n"
                            ++ Debug.toString expected
                            ++ "\nActual\n"
                            ++ Debug.toString actual
            )


type JsonOrYaml
    = JSON
    | YAML


globTestRouteNew : ApiRoute ApiRoute.Response
globTestRouteNew =
    ApiRoute.succeed
        (Request.succeed
            (globTestsNew
                |> DataSource.combine
                |> DataSource.map
                    (\testResults ->
                        case
                            testResults
                                |> Result.Extra.combine
                        of
                            Ok _ ->
                                Response.plainText
                                    ("Pass\n"
                                        ++ String.fromInt (List.length testResults)
                                        ++ " successful tests"
                                    )

                            Err error ->
                                ("Fail\n\n" ++ error)
                                    |> Response.plainText
                                    |> Response.withStatusCode 500
                    )
            )
        )
        |> ApiRoute.literal "tests"
        |> ApiRoute.serverRender
