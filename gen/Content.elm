module Content exposing (Content, allData, buildAllData, lookup)

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
            (String.split "/" url.path
                |> List.drop 1
            )
                == path
        )
        (content.pages ++ content.posts)
        |> Maybe.map Tuple.second


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
                    pages
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


allData : Result (Element msg) (Content msg)
allData =
    case posts of
        Ok postListings ->
            let
                pageListings =
                    pages
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


renderErrors : List Mark.Error.Error -> Element msg
renderErrors errors =
    errors
        |> List.map (Mark.Error.toHtml Mark.Error.Light)
        |> List.map Element.html
        |> Element.column []


pages : List ( List String, String )
pages =
    [ ( [ "" ]
      , """|> Article
    author = Dillon Kearns
    title = Home Page
    tags = software other
    description =
        How I learned to use elm-markup.

This is the home page.
"""
      )
    , ( [ "services" ]
      , """|> Article
    author = Dillon Kearns
    title = Services
    tags = software other
    description =
        How I learned to use elm-markup.

Here are the services I offer.
"""
      )
    , ( [ "about" ]
      , """|> Article
    author = Dillon Kearns
    title = How I Learned /elm-markup/
    tags = software other
    description =
        How I learned to use elm-markup.

dummy text of the printing and [typesetting industry]{link| url = http://mechanical-elephant.com }. Lorem Ipsum has been the industrys standard dummy text ever since the 1500s, when an unknown printer took a galley of type and scrambled it to make a type specimen book. It has survived not only five centuries, but also the leap into electronic typesetting, remaining essentially unchanged. It was popularised in the 1960s with the release of Letraset sheets containing Lorem Ipsum passages, and more recently with desktop publishing software like Aldus PageMaker including versions of Lorem Ipsum.
Lorem ipsum dolor sit amet, consectetur adipiscing elit. In id pellentesque elit, id sollicitudin felis. Morbi eu risus molestie enim suscipit auctor. Morbi pharetra, nisl ut finibus ornare, dolor tortor aliquet est, quis feugiat odio sem ut sem. Nullam eu bibendum ligula. Nunc mollis tortor ac rutrum interdum. Nunc ultrices risus eu pretium interdum. Nullam maximus convallis quam vitae ullamcorper. Praesent sapien nulla, hendrerit quis tincidunt a, placerat et felis. Nullam consectetur magna nec lacinia egestas. Aenean rutrum nunc diam.
Morbi ut porta justo. Integer ac eleifend sem. Fusce sed auctor velit, et condimentum quam. Vivamus id mollis libero, mattis commodo mauris. In hac habitasse platea dictumst. Duis eu lobortis arcu, ac volutpat ante. Duis sapien enim, auctor vitae semper vitae, tincidunt et justo. Cras aliquet turpis nec enim mattis finibus. Nulla diam urna, semper ut elementum at, porttitor ut sapien. Pellentesque et dui neque. In eget lectus odio. Fusce nulla velit, eleifend sit amet malesuada ac, hendrerit id neque. Curabitur blandit elit et urna fringilla, id commodo quam fermentum.
But for real, here's a kitten.


|> Image
    src = http://placekitten.com/g/200/300
    description = What a cute kitten.
Lorem ipsum dolor sit amet, consectetur adipiscing elit. In id pellentesque elit, id sollicitudin felis. Morbi eu risus molestie enim suscipit auctor. Morbi pharetra, nisl ut finibus ornare, dolor tortor aliquet est, quis feugiat odio sem ut sem. Nullam eu bibendum ligula. Nunc mollis tortor ac rutrum interdum. Nunc ultrices risus eu pretium interdum. Nullam maximus convallis quam vitae ullamcorper. Praesent sapien nulla, hendrerit quis tincidunt a, placerat et felis. Nullam consectetur magna nec lacinia egestas. Aenean rutrum nunc diam.
Morbi ut porta justo. Integer ac eleifend sem. Fusce sed auctor velit, et condimentum quam. Vivamus id mollis libero, mattis commodo mauris. In hac habitasse platea dictumst. Duis eu lobortis arcu, ac volutpat ante. Duis sapien enim, auctor vitae semper vitae, tincidunt et justo. Cras aliquet turpis nec enim mattis finibus. Nulla diam urna, semper ut elementum at, porttitor ut sapien. Pellentesque et dui neque. In eget lectus odio. Fusce nulla velit, eleifend sit amet malesuada ac, hendrerit id neque. Curabitur blandit elit et urna fringilla, id commodo quam fermentum.

|> Code
    This is a code block
    With Multiple lines

|> H1
    Articles


|> IndexContent
    posts = articles

Here are a few articles you might like.

|> H1
    My section on /lists/

What does a *list* look like?

|> List
    1.  This is definitely the first thing.
        Add all together now
        With some Content
    -- Another thing.
        1. sublist
        -- more sublist
            -- indented
        -- other sublist
            -- subthing
            -- other subthing
    -- and yet, another
        --  and another one
            With some content
  """
      )
    , ( [ "articles" ]
      , """|> Article
    author = Matthew Griffith
    title = How I Learned /elm-markup/
    tags = software other
    description =
        How I learned to use elm-markup.


Here are some articles. You can learn more at.....

|> IndexContent
    posts = articles"""
      )
    ]


posts :
    Result (List Mark.Error.Error)
        (List
            ( List String
            , { body : List (Element msg)
              , metadata : MarkParser.Metadata msg
              }
            )
        )
posts =
    [ ( [ "articles", "gatekeepers" ]
      , """|> Article
    author = Dillon Kearns
    title = Gatekeepers
    tags = software other
    description =
        How I learned to use elm-markup.

  Here is an article.
  """
      )
    , ( [ "articles", "tiny-steps" ]
      , """|> Article
    author = Dillon Kearns
    title = Moving Faster with Tiny Steps in Elm
    tags = software other
    description =
        How I learned to use elm-markup.

|> Image
    src = mountains.jpg
    description = The Elm Architecture


In this post, we’re going to be looking up an Article in an Elm Dict, using the tiniest steps possible.

Why use tiny steps? Simple! Because we want to write Elm code faster, and with more precise error messages to guide us through each step.

|> H2
    Setting Up Your Environment

The point of taking tiny steps is that you get constant, clear feedback. So before I walk through the steps, here are some things to set up in your editor to help you get more feedback:

|> List
    -- See Elm compiler errors instantly without manually running a command. For example, have elm-make run whenever your files change. Or run elm-live, webpack, or parcel in watch mode.
    -- Even better, get error messages in your editor whenever you save. Here are some instructions for configuring Atom with in-editor compiler errors.
    -- Note that with both of these workflows, I recommend saving constantly so you get instant error messages.
    -- Atom also gives you auto-completion, which is another helpful form of feedback. Elm-IntelliJ is another good option for this.


Let me know how this technique goes! I’ve gotten a lot of great feedback from my clients about this approach, and I love hearing success stories. Hit reply and let me know how it goes! I’d love to hear how you’re able to apply this in your day-to-day work!"""
      )
    ]
        |> List.map (\( path, markup ) -> ( path, Mark.compile (MarkParser.document Element.none) markup ))
        |> combineResults


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
        Result (List Mark.Error.Error)
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
                        Err partial.errors

                    Mark.Failure failures ->
                        Err failures
            )
        |> Result.Extra.combine
