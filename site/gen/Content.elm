module Content exposing (Content, buildAllData, lookup)

import Element exposing (Element)
import Index
import List.Extra
import Mark
import Mark.Error
import MarkParser
import Result.Extra
import Url exposing (Url)


lookup :
    Content msg
    -> Url
    ->
        Maybe
            { body : List (Element msg)
            , metadata : MarkParser.Metadata msg
            }
lookup content url =
    List.Extra.find
        (\( path, markup ) ->
            (String.split "/" (url.path |> dropTrailingSlash)
                |> List.drop 1
            )
                == path
        )
        (content.pages ++ content.posts)
        |> Maybe.map Tuple.second


dropTrailingSlash path =
    if path |> String.endsWith "/" then
        String.dropRight 1 path

    else
        path


type alias Content msg =
    { posts :
        List
            ( List String
            , { body : List (Element msg)
              , metadata : MarkParser.Metadata msg
              }
            )
    , pages :
        List
            ( List String
            , { body : List (Element msg)
              , metadata : MarkParser.Metadata msg
              }
            )
    }


buildAllData :
    { pages : List ( List String, String ), posts : List ( List String, String ) }
    -> Result (Element msg) (Content msg)
buildAllData record =
    case
        record.posts
            |> List.map (\( path, markup ) -> ( path, Mark.compile (MarkParser.document Element.none) markup ))
            |> combineResults
    of
        Ok postListings ->
            let
                pageListings =
                    record.pages
                        |> List.map
                            (\( path, markup ) ->
                                ( path
                                , Mark.compile
                                    (MarkParser.document
                                        (Index.view postListings)
                                    )
                                    markup
                                )
                            )
                        |> combineResults
            in
            case pageListings of
                Ok successPageListings ->
                    Ok
                        { posts = postListings
                        , pages = successPageListings
                        }

                Err errors ->
                    Err (renderErrors errors)

        Err errors ->
            Err (renderErrors errors)


renderErrors : ( List String, List Mark.Error.Error ) -> Element msg
renderErrors ( path, errors ) =
    Element.column []
        [ Element.text (path |> String.join "/")
        , errors
            |> List.map (Mark.Error.toHtml Mark.Error.Light)
            |> List.map Element.html
            |> Element.column []
        ]


combineResults :
    List
        ( List String
        , Mark.Outcome (List Mark.Error.Error)
            (Mark.Partial
                { body : List (Element msg)
                , metadata : MarkParser.Metadata msg
                }
            )
            { body : List (Element msg)
            , metadata : MarkParser.Metadata msg
            }
        )
    ->
        Result ( List String, List Mark.Error.Error )
            (List
                ( List String
                , { body : List (Element msg)
                  , metadata : MarkParser.Metadata msg
                  }
                )
            )
combineResults list =
    list
        |> List.map
            (\( path, outcome ) ->
                case outcome of
                    Mark.Success parsedMarkup ->
                        Ok ( path, parsedMarkup )

                    Mark.Almost partial ->
                        -- Err "Almost"
                        Err ( path, partial.errors )

                    Mark.Failure failures ->
                        Err ( path, failures )
            )
        |> Result.Extra.combine
