{- Copied from https://github.com/matheus23/elm-markdown-transforms/blob/02fddd3bf9e82412eb289bead3b5124a98163ab6/src/Markdown/Scaffolded.elm
   Modified to use BackendTask instead of StaticHttp
-}


module Markdown.Scaffolded exposing
    ( Block(..)
    , map, indexedMap
    , parameterized, validating, withBackendTask
    , reduceHtml, reduceWords, reducePretty, reduce
    , foldFunction, foldResults, foldStaticHttpRequests, foldIndexed
    , fromRenderer, toRenderer
    , bumpHeadings
    )

{-|


# Rendering Markdown with Scaffolds, Reducers and Folds

(This is called recursion-schemes in other languages, but don't worry, you don't have to
write recursive functions (this is the point of all of this ;) )!)

This is module provides a more **complicated**, but also **more powerful and
composable** way of rendering markdown than the built-in elm-markdown
[`Renderer`](https://package.elm-lang.org/packages/dillonkearns/elm-markdown/latest/Markdown-Renderer).

If you feel a little overwhelmed with this module at first, I recommend taking a look at
the [What are reducers?](#what-are-reducers-) section.


# Main Datastructure

@docs Block

@docs map, indexedMap


# High-level Transformations

These functions are not as composable as [transformation building blocks](#transformation-building-blocks),
but might suffice for your use case. Take a look at the other section if you find you need
something better.

@docs parameterized, validating, withBackendTask


# Transformation Building Blocks

@docs reduceHtml, reduceWords, reducePretty, reduce
@docs foldFunction, foldResults, foldStaticHttpRequests, foldIndexed


### What are 'reducers'?

In this context of the library, we're often working with functions of the type
`Block view -> view`, where `view` might be something like `Html Msg` or `String`, etc.
or, generally, functions of structure `Block a -> b`.

I refer to functions of that structure as 'reducers'. (This is somewhat different to the
'real' terminology, but I feel like they capture the nature of 'reducing once' very well.)

If you know `List.foldr` you already know an example for a reducer (the first argument)!
The reducers in this module are no different, we just write them in different ways.

We can do the same thing we did for this library for lists:

    type ListScaffold elem a
        = Empty
        | Cons elem a

    reduceEmpty = 0

    reduceCons a b = a + b

    handler listElement =
        case listElement of
            Empty ->
                reduceEmpty

            Cons elem accumulated ->
                reduceCons elem accumulated

    foldl : (ListScaffold a b -> b) -> List a -> b
    foldl handle list =
        case list of
            [] -> handle Empty
            (x:xs) -> handle (Cons x xs)

    foldl handler == List.foldl reduceCons reduceEmpty

The last line illustrates how different ways of writing these reducers relate: For
`List.foldl` we simply provide the cases (empty or cons) as different arguments,
for reducers in this library, we create a custom type case for empty and cons.


### What are 'folds'?

Some functions have similar, but not quite the type that a reducers has. For example:

  - `Block (Request a) -> Request (Block a)`
  - `Block (Maybe a) -> Maybe (Block a)`
  - `Block (Result err a) -> Result err (Block a)`
  - `Block (environment -> a) -> environment -> Block a`

All of these examples have the structure `Block (F a) -> F (Block a)` for some `F`. You
might have to squint your eyes at the last two of these examples. Especially the last one.
Let me rewrite it with a type alias:

    type alias Function a b =
        a -> b

    foldFunction : Block (Function env a) -> Function env (Block a)


### Combining Reducers

You can combine multiple 'reducers' into one. There's no function for doing this, but a
pattern you might want to follow.

Let's say you want to accumulate both all the words in your markdown and the `Html` you
want it to render to, then you can do this:

    type alias Rendered =
        { html : Html Msg
        , words : List String
        }

    reduceRendered : Block Rendered -> Rendered
    reduceRendered block =
        { html = block |> map .html |> reduceHtml
        , words = block |> map .words |> reduceWords
        }

If you want to render to more things, just add another parameter to the record type and
follow the pattern. It is even possible to let the rendered html to depend on the words
inside itself (or maybe something else you're additionally reducing to).


# Conversions

Did you already start to write a custom elm-markdown `Renderer`, but want to use this
library? Don't worry. They're compatible. You can convert between them!

@docs fromRenderer, toRenderer


# Utilities

I mean to aggregate utilites for transforming Blocks in this section.

@docs bumpHeadings

-}

import BackendTask exposing (BackendTask)
import Html exposing (Html)
import Html.Attributes as Attr
import Markdown.Block as Block
import Markdown.Html
import Markdown.Renderer exposing (Renderer)
import Regex
import Result.Extra as Result



-- EXPOSED DEFINITIONS


{-| A datatype that enumerates all possible ways markdown could wrap some children.

Kind of like a 'Scaffold' around something that's already built, which will get torn down
after building is finished.

This does not include Html tags.

If you look at the left hand sides of all of the functions in the elm-markdown
[`Renderer`](https://package.elm-lang.org/packages/dillonkearns/elm-markdown/latest/Markdown-Renderer),
you'll notice a similarity to this custom type, except it's missing a type for 'html'.

Defining this data structure has some advantages in composing multiple Renderers.

It has a type parameter `children`, which is supposed to be filled with `String`,
`Html msg` or similar. Take a look at some [reducers](#transformation-building-blocks) for examples of this.

There are some neat tricks you can do with this data structure, for example, `Block Never`
represents only non-nested blocks of markdown.

-}
type Block children
    = Heading { level : Block.HeadingLevel, rawText : String, children : List children }
    | Paragraph (List children)
    | BlockQuote (List children)
    | Text String
    | CodeSpan String
    | Strong (List children)
    | Emphasis (List children)
    | Strikethrough (List children)
    | Link { title : Maybe String, destination : String, children : List children }
    | Image { alt : String, src : String, title : Maybe String }
    | UnorderedList { items : List (Block.ListItem children) }
    | OrderedList { startingIndex : Int, items : List (List children) }
    | CodeBlock { body : String, language : Maybe String }
    | HardLineBreak
    | ThematicBreak
    | Table (List children)
    | TableHeader (List children)
    | TableBody (List children)
    | TableRow (List children)
    | TableCell (Maybe Block.Alignment) (List children)
    | TableHeaderCell (Maybe Block.Alignment) (List children)


{-| Transform each child of a `Block` using the given function.

For example, we can transform the lists of words inside each block into concatenated
Strings:

    wordsToWordlist : Block (List String) -> Block String
    wordsToWordlist block =
        map (\listOfWords -> String.join ", " listOfWords)
            block

    Paragraph
        [ [ "This", "paragraph", "was", "full", "of", "individual", "words", "once." ]
        , [ "It", "also", "contained", "another", "paragraph" ]
        ]
        |> wordsToWordlist
    --> Paragraph
    -->     [ "This, paragraph, was, full, of, individual, words, once."
    -->     , "It, also, contained, another, paragraph"
    -->     ]

    HardLineBreak |> wordsToWordlist
    --> HardLineBreak

The ability to define this function is one of the reasons for our `Block` definition. If
you try defining `map` for elm-markdown's `Renderer` you'll find out it doesn't work.

-}
map : (a -> b) -> Block a -> Block b
map f markdown =
    case markdown of
        Heading { level, rawText, children } ->
            Heading { level = level, rawText = rawText, children = List.map f children }

        Paragraph children ->
            Paragraph (List.map f children)

        BlockQuote children ->
            BlockQuote (List.map f children)

        Text content ->
            Text content

        CodeSpan content ->
            CodeSpan content

        Strong children ->
            Strong (List.map f children)

        Emphasis children ->
            Emphasis (List.map f children)

        Strikethrough children ->
            Strikethrough (List.map f children)

        Link { title, destination, children } ->
            Link { title = title, destination = destination, children = List.map f children }

        Image imageInfo ->
            Image imageInfo

        UnorderedList { items } ->
            UnorderedList
                { items =
                    List.map
                        (\(Block.ListItem task children) ->
                            Block.ListItem task (List.map f children)
                        )
                        items
                }

        OrderedList { startingIndex, items } ->
            OrderedList { startingIndex = startingIndex, items = List.map (List.map f) items }

        CodeBlock codeBlockInfo ->
            CodeBlock codeBlockInfo

        HardLineBreak ->
            HardLineBreak

        ThematicBreak ->
            ThematicBreak

        Table children ->
            Table (List.map f children)

        TableHeader children ->
            TableHeader (List.map f children)

        TableBody children ->
            TableBody (List.map f children)

        TableRow children ->
            TableRow (List.map f children)

        TableCell alignment children ->
            TableCell alignment (List.map f children)

        TableHeaderCell alignment children ->
            TableHeaderCell alignment (List.map f children)


{-| Block's children are mapped from 0 to n (if n+1 is the amount of children).

Most arguments to the mapping function are therefore [0], [1], ... etc.

All children will get unique `List Int` arguments.

In some cases like lists, there might be two levels of indices: [0,0], or [1,0].

In these cases, the first integer is the 'closest' index from the point of view of the
child.

    OrderedList
        { startingIndex = 0
        , items =
            [ [ (), () ]
            , [ (), (), () ]
            ]
        }
        |> indexedMap (\indices _ -> indices)
    --> OrderedList
    -->     { startingIndex = 0
    -->     , items =
    -->         [ [ [ 0, 0 ], [ 1, 0 ] ]
    -->         , [ [ 0, 1 ], [ 1, 1 ], [ 2, 1 ] ]
    -->         ]
    -->     }

-}
indexedMap : (List Int -> a -> b) -> Block a -> Block b
indexedMap f markdown =
    case markdown of
        Heading { level, rawText, children } ->
            Heading { level = level, rawText = rawText, children = List.indexedMap (\index -> f [ index ]) children }

        Paragraph children ->
            Paragraph (List.indexedMap (\index -> f [ index ]) children)

        BlockQuote children ->
            BlockQuote (List.indexedMap (\index -> f [ index ]) children)

        Text content ->
            Text content

        CodeSpan content ->
            CodeSpan content

        Strong children ->
            Strong (List.indexedMap (\index -> f [ index ]) children)

        Emphasis children ->
            Emphasis (List.indexedMap (\index -> f [ index ]) children)

        Strikethrough children ->
            Strikethrough (List.indexedMap (\index -> f [ index ]) children)

        Link { title, destination, children } ->
            Link { title = title, destination = destination, children = List.indexedMap (\index -> f [ index ]) children }

        Image imageInfo ->
            Image imageInfo

        UnorderedList { items } ->
            UnorderedList
                { items =
                    List.indexedMap
                        (\indexA (Block.ListItem task children) ->
                            Block.ListItem task (List.indexedMap (\indexB -> f [ indexB, indexA ]) children)
                        )
                        items
                }

        OrderedList { startingIndex, items } ->
            OrderedList { startingIndex = startingIndex, items = List.indexedMap (\indexA -> List.indexedMap (\indexB -> f [ indexB, indexA ])) items }

        CodeBlock codeBlockInfo ->
            CodeBlock codeBlockInfo

        HardLineBreak ->
            HardLineBreak

        ThematicBreak ->
            ThematicBreak

        Table children ->
            Table (List.indexedMap (\index -> f [ index ]) children)

        TableHeader children ->
            TableHeader (List.indexedMap (\index -> f [ index ]) children)

        TableBody children ->
            TableBody (List.indexedMap (\index -> f [ index ]) children)

        TableRow children ->
            TableRow (List.indexedMap (\index -> f [ index ]) children)

        TableCell alignment children ->
            TableCell alignment (List.indexedMap (\index -> f [ index ]) children)

        TableHeaderCell alignment children ->
            TableHeaderCell alignment (List.indexedMap (\index -> f [ index ]) children)


{-| Use this function if you want to parameterize your view by an environment.

Another way of thinking about this use-case is: use this if you want to 'render to
functions'.

Examples for what the `environment` type variable can be:

  - A `Model`, for rendering to `Model -> Html Msg` for `view`.
  - Templating information, in case you want to use markdown as templates and want to
    render to a function that expects templating parameters.

Usually, for the above usecases you would have to define a function of type

    reduceTemplate :
        Block (TemplateInfo -> Html msg)
        -> (TemplateInfo -> Html msg)

for example, so that you can turn it back into a `Renderer (Template Info -> Html msg)`
for elm-markdown.

If you were to define such a function, you would have to pass around the `TemplateInfo`
parameter a lot. This function will take care of that for you.


### Anti use-cases

In some cases using this function would be overkill. The alternative to this function is
to simply parameterize your whole renderer (and not use this library):

    renderMarkdown : List String -> Block (Html Msg) -> Html Msg
    renderMarkdown censoredWords markdown =
        ...

    renderer : List String -> Markdown.Renderer (Html Msg)
    renderer censoredWords =
        toRenderer
            { renderHtml = ...
            , renderMarkdown = renderMarkdown censoredWords
            }

In this example you can see how we pass through the 'censored words'. It behaves kind of
like some global context in which we create our renderer.

It is hard to convey the abstract notion of when to use `parameterized` and when not to.
I'll give it a try: If you want to parse your markdown once and need to quickly render
different versions of it (for example with different `Model`s or different
`TemplateInfo`s), then use this. In other cases, if you probably only want to de-couple
some variable out of your renderer that is pretty static in general (for example censored
words), don't use this.


### `parameterized` over multiple Parameters

If you want to parameterize your renderer over multiple variables, there are two options:

1.  Add a field to the `environment` type used in this function
2.  Take another parameter in curried form

Although both are possible, I highly recommend the first option, as it is by far easier
to deal with only one call to `parameterized`, not with two calls that would be required
for option 2.


### Missing Functionality

If this function doesn't quite do what you want, just try to re-create what you need by
using `map` directly. `parameterized` basically just documents a pattern that is really
easy to re-create: Its implementation is just 1 line of code.

-}
parameterized :
    (Block view -> environment -> view)
    -> (Block (environment -> view) -> (environment -> view))
parameterized reducer markdown env =
    reducer (map (\expectingEnv -> expectingEnv env) markdown) env


{-| This transform enables validating the content of your `Block` before
rendering.

This function's most prominent usecases are linting markdown files, so for example:

  - Make sure all your code snippets are specified only with valid languages
    ('elm', 'javascript', 'js', 'html' etc.)
  - Make sure all your links are `https://` links
  - Generate errors/warnings on typos or words not contained in a dictionary
  - Disallow `h1` (alternatively, consider bumping the heading level)

But it might also be possible that your `view` type can't _always_ be reduced from a
`Block view` to a `view`, so you need to generate an error in these cases.


### Missing Functionality

If this function doesn't quite do what you need to do, try using `foldResults`.
The `validating` definition basically just documents a common pattern. Its implementation
is just 1 line of code.

-}
validating :
    (Block view -> Result error view)
    -> (Block (Result error view) -> Result error view)
validating reducer markdown =
    markdown |> foldResults |> Result.andThen reducer


{-| This transform allows you to perform elm-pages' BackendTask requests without having to
think about how to thread these through your renderer.

Some applications that can be realized like this:

  - Verifying that all links in your markdown do resolve at page build-time
    (Note: This currently needs some change in elm-pages, so it's not possible _yet_)
  - Giving custom elm-markdown HTML elements the ability to perform BackendTask requests


### Missing Functionality

If this function doesn't quite do what you need to do, try using `foldStaticHttpRequests`.
The `wihtStaticHttpRequests` definition basically just documents a common pattern.
Its implementation is just 1 line of code.

-}
withBackendTask :
    (Block view -> BackendTask view)
    -> (Block (BackendTask view) -> BackendTask view)
withBackendTask reducer markdown =
    markdown |> foldStaticHttpRequests |> BackendTask.andThen reducer


{-| This will reduce a `Block` to `Html` similar to what the
[`defaultHtmlRenderer` in elm-markdown](https://package.elm-lang.org/packages/dillonkearns/elm-markdown/latest/Markdown-Renderer#defaultHtmlRenderer)
does. That is, it renders similar to what the CommonMark spec expects.

It also takes a list of attributes for convenience, so if you want to attach styles,
id's, classes or events, you can use this.

However, **the attributes parameter is ignored for `Text` nodes**.

-}
reduceHtml : List (Html.Attribute msg) -> Block (Html msg) -> Html msg
reduceHtml attributes markdown =
    let
        attrsFromAlignment maybeAlignment =
            case maybeAlignment of
                Just Block.AlignLeft ->
                    Attr.align "left" :: attributes

                Just Block.AlignCenter ->
                    Attr.align "center" :: attributes

                Just Block.AlignRight ->
                    Attr.align "right" :: attributes

                Nothing ->
                    attributes
    in
    case markdown of
        Heading { level, children } ->
            case level of
                Block.H1 ->
                    Html.h1 attributes children

                Block.H2 ->
                    Html.h2 attributes children

                Block.H3 ->
                    Html.h3 attributes children

                Block.H4 ->
                    Html.h4 attributes children

                Block.H5 ->
                    Html.h5 attributes children

                Block.H6 ->
                    Html.h6 attributes children

        Paragraph children ->
            Html.p attributes children

        BlockQuote children ->
            Html.blockquote attributes children

        Text content ->
            Html.text content

        CodeSpan content ->
            Html.code attributes [ Html.text content ]

        Strong children ->
            Html.strong attributes children

        Emphasis children ->
            Html.em attributes children

        Strikethrough children ->
            Html.span (Attr.style "text-decoration" "line-through" :: attributes) children

        Link link ->
            case link.title of
                Just title ->
                    Html.a
                        (Attr.href link.destination
                            :: Attr.title title
                            :: attributes
                        )
                        link.children

                Nothing ->
                    Html.a (Attr.href link.destination :: attributes) link.children

        Image imageInfo ->
            case imageInfo.title of
                Just title ->
                    Html.img
                        (Attr.src imageInfo.src
                            :: Attr.alt imageInfo.alt
                            :: Attr.title title
                            :: attributes
                        )
                        []

                Nothing ->
                    Html.img
                        (Attr.src imageInfo.src
                            :: Attr.alt imageInfo.alt
                            :: attributes
                        )
                        []

        UnorderedList { items } ->
            Html.ul attributes
                (items
                    |> List.map
                        (\item ->
                            case item of
                                Block.ListItem task children ->
                                    let
                                        checkbox =
                                            case task of
                                                Block.NoTask ->
                                                    Html.text ""

                                                Block.IncompleteTask ->
                                                    Html.input
                                                        [ Attr.disabled True
                                                        , Attr.checked False
                                                        , Attr.type_ "checkbox"
                                                        ]
                                                        []

                                                Block.CompletedTask ->
                                                    Html.input
                                                        [ Attr.disabled True
                                                        , Attr.checked True
                                                        , Attr.type_ "checkbox"
                                                        ]
                                                        []
                                    in
                                    Html.li [] (checkbox :: children)
                        )
                )

        OrderedList { startingIndex, items } ->
            Html.ol
                (case startingIndex of
                    1 ->
                        Attr.start startingIndex :: attributes

                    _ ->
                        attributes
                )
                (items
                    |> List.map
                        (\itemBlocks ->
                            Html.li []
                                itemBlocks
                        )
                )

        CodeBlock { body } ->
            Html.pre attributes
                [ Html.code []
                    [ Html.text body
                    ]
                ]

        HardLineBreak ->
            Html.br attributes []

        ThematicBreak ->
            Html.hr attributes []

        Table children ->
            Html.table attributes children

        TableHeader children ->
            Html.thead attributes children

        TableBody children ->
            Html.tbody attributes children

        TableRow children ->
            Html.tr attributes children

        TableHeaderCell maybeAlignment children ->
            Html.th (attrsFromAlignment maybeAlignment) children

        TableCell maybeAlignment children ->
            Html.td (attrsFromAlignment maybeAlignment) children


{-| Transform a block that contains functions into a function that produces blocks.

One really common use-case is having access to a `Model` inside your html renderers.
In these cases you want your markdown to be 'rendered to a function'.

So let's say you've got a
[`Markdown.Html.Renderer`]()
like so:

    renderHtml :
        Markdown.Html.Renderer
            (List (Model -> Html Msg)
             -> (Model -> Html Msg)
            )

It has this type to be able to depend on the `Model`. Eventually you'll want to render to
`Model -> Html Msg`.

So now you can define your
[`Markdown.Renderer.Renderer`]()
like so:


    renderer : Markdown.Renderer.Renderer (Model -> Html Msg)
    renderer =
        toRenderer
            { renderHtml = renderHtml
            , renderMarkdown = renderMarkdown
            }

    renderMarkdown :
        Block (Model -> Html Msg)
        -> (Model -> Html Msg)
    renderMarkdown block model =
        foldFunction block
            -- ^ result : Model -> Block (Html Msg)
            model
            -- ^ result : Block (Html Msg)
            |> reduceHtml

    -- ^ result : Html Msg

-}
foldFunction : Block (environment -> view) -> (environment -> Block view)
foldFunction markdown environment =
    markdown |> map ((|>) environment)


{-| Fold your blocks with index information. This uses [`indexedMap`](#indexedMap) under
the hood.

This is quite advanced, but also very useful. If you're looking for a working example,
please take a look at the test for this function.

-}
foldIndexed : Block (List Int -> view) -> (List Int -> Block view)
foldIndexed markdown pathSoFar =
    markdown |> indexedMap (\indices view -> view (indices ++ pathSoFar))


{-| Extracts all words from the blocks and inlines. Excludes any markup characters, if
they had an effect on the markup.

The words are split according to the `\s` javascript regular expression (regex).

Inline code spans are split, but **code blocks fragments are ignored** (code spans are
included).

If you need something more specific, I highly recommend rolling your own function for
this.

This is useful if you need to e.g. create header slugs.

-}
reduceWords : Block (List String) -> List String
reduceWords =
    let
        whitespace =
            Regex.fromStringWith { caseInsensitive = True, multiline = True } "\\s"
                |> Maybe.withDefault Regex.never

        words =
            Regex.split whitespace

        extractWords block =
            case block of
                Text content ->
                    words content

                CodeSpan content ->
                    words content

                _ ->
                    []
    in
    reduce
        { extract = extractWords
        , accumulate = List.concat
        }


{-| Thread results through your Blocks.

The input is a block that contains possibly failed views. The output becomes `Err`, if
any of the input block's children had an error (then it's the first error).
If all of the block's children were `Ok`, then the result is going to be `Ok`.

-}
foldResults : Block (Result error view) -> Result error (Block view)
foldResults markdown =
    case markdown of
        Heading { level, rawText, children } ->
            children
                |> Result.combine
                |> Result.map
                    (\chdr ->
                        Heading { level = level, rawText = rawText, children = chdr }
                    )

        Paragraph children ->
            children
                |> Result.combine
                |> Result.map Paragraph

        BlockQuote children ->
            children
                |> Result.combine
                |> Result.map BlockQuote

        Text content ->
            Text content
                |> Ok

        CodeSpan content ->
            CodeSpan content
                |> Ok

        Strong children ->
            children
                |> Result.combine
                |> Result.map Strong

        Emphasis children ->
            children
                |> Result.combine
                |> Result.map Emphasis

        Strikethrough children ->
            children
                |> Result.combine
                |> Result.map Strikethrough

        Link { title, destination, children } ->
            children
                |> Result.combine
                |> Result.map
                    (\chdr ->
                        Link { title = title, destination = destination, children = chdr }
                    )

        Image imageInfo ->
            Image imageInfo
                |> Ok

        UnorderedList { items } ->
            items
                |> List.map
                    (\(Block.ListItem task children) ->
                        children
                            |> Result.combine
                            |> Result.map (Block.ListItem task)
                    )
                |> Result.combine
                |> Result.map (\itms -> UnorderedList { items = itms })

        OrderedList { startingIndex, items } ->
            items
                |> List.map Result.combine
                |> Result.combine
                |> Result.map
                    (\itms ->
                        OrderedList { startingIndex = startingIndex, items = itms }
                    )

        CodeBlock codeBlockInfo ->
            CodeBlock codeBlockInfo
                |> Ok

        HardLineBreak ->
            HardLineBreak
                |> Ok

        ThematicBreak ->
            ThematicBreak
                |> Ok

        Table children ->
            children
                |> Result.combine
                |> Result.map Table

        TableHeader children ->
            children
                |> Result.combine
                |> Result.map TableHeader

        TableBody children ->
            children
                |> Result.combine
                |> Result.map TableBody

        TableRow children ->
            children
                |> Result.combine
                |> Result.map TableRow

        TableHeaderCell maybeAlignment children ->
            children
                |> Result.combine
                |> Result.map (TableHeaderCell maybeAlignment)

        TableCell maybeAlignment children ->
            children
                |> Result.combine
                |> Result.map (TableCell maybeAlignment)


{-| Accumulate elm-page's
[`BackendTask`](https://package.elm-lang.org/packages/dillonkearns/elm-pages/latest/Pages-BackendTask#Request)s
over blocks.

Using this, it is possible to write reducers that produce views as a result of performing
static http requests.

-}
foldStaticHttpRequests : Block (BackendTask view) -> BackendTask (Block view)
foldStaticHttpRequests markdown =
    case markdown of
        Heading { level, rawText, children } ->
            children
                |> allStaticHttp
                |> BackendTask.map
                    (\chdr ->
                        Heading { level = level, rawText = rawText, children = chdr }
                    )

        Paragraph children ->
            children
                |> allStaticHttp
                |> BackendTask.map Paragraph

        BlockQuote children ->
            children
                |> allStaticHttp
                |> BackendTask.map BlockQuote

        Text content ->
            Text content
                |> BackendTask.succeed

        CodeSpan content ->
            CodeSpan content
                |> BackendTask.succeed

        Strong children ->
            children
                |> allStaticHttp
                |> BackendTask.map Strong

        Emphasis children ->
            children
                |> allStaticHttp
                |> BackendTask.map Emphasis

        Strikethrough children ->
            children
                |> allStaticHttp
                |> BackendTask.map Strikethrough

        Link { title, destination, children } ->
            children
                |> allStaticHttp
                |> BackendTask.map
                    (\chdr ->
                        Link { title = title, destination = destination, children = chdr }
                    )

        Image imageInfo ->
            Image imageInfo
                |> BackendTask.succeed

        UnorderedList { items } ->
            items
                |> List.map
                    (\(Block.ListItem task children) ->
                        children
                            |> allStaticHttp
                            |> BackendTask.map (Block.ListItem task)
                    )
                |> allStaticHttp
                |> BackendTask.map (\itms -> UnorderedList { items = itms })

        OrderedList { startingIndex, items } ->
            items
                |> List.map allStaticHttp
                |> allStaticHttp
                |> BackendTask.map
                    (\itms ->
                        OrderedList { startingIndex = startingIndex, items = itms }
                    )

        CodeBlock codeBlockInfo ->
            CodeBlock codeBlockInfo
                |> BackendTask.succeed

        HardLineBreak ->
            HardLineBreak
                |> BackendTask.succeed

        ThematicBreak ->
            ThematicBreak
                |> BackendTask.succeed

        Table children ->
            children
                |> allStaticHttp
                |> BackendTask.map Table

        TableHeader children ->
            children
                |> allStaticHttp
                |> BackendTask.map TableHeader

        TableBody children ->
            children
                |> allStaticHttp
                |> BackendTask.map TableBody

        TableRow children ->
            children
                |> allStaticHttp
                |> BackendTask.map TableRow

        TableHeaderCell maybeAlignment children ->
            children
                |> allStaticHttp
                |> BackendTask.map (TableHeaderCell maybeAlignment)

        TableCell maybeAlignment children ->
            children
                |> allStaticHttp
                |> BackendTask.map (TableCell maybeAlignment)


{-| Convert a block of markdown back to markdown text.
(See the 'Formatting Markdown' test in the test suite.)

This just renders one particular style of markdown. Your use-case might need something
completely different. I recommend taking a look at the source code and adapting it to
your needs.

Note: **This function doesn't support GFM tables**.
The function `Markdown.PrettyTables.reducePrettyTable` extends this function with table
pretty-printing.
Table pretty-printing is complicated, even when ignoring column sizes. The type
`Block String -> String` is just "not powerful" enough to render a table to a string in
such a way that it is syntactically valid again.

-}
reducePretty : Block String -> String
reducePretty block =
    let
        escape toEscape =
            String.replace toEscape ("\\" ++ toEscape)
    in
    case block of
        Heading { level, children } ->
            (case level of
                Block.H1 ->
                    "# "

                Block.H2 ->
                    "## "

                Block.H3 ->
                    "### "

                Block.H4 ->
                    "#### "

                Block.H5 ->
                    "##### "

                Block.H6 ->
                    "###### "
            )
                ++ String.concat children

        Text content ->
            content

        Paragraph children ->
            String.concat children

        BlockQuote children ->
            children
                |> String.concat
                |> String.split "\n"
                |> List.map (\line -> "> " ++ line)
                |> String.join "\n"

        Strong children ->
            -- TODO Escaping
            "**" ++ String.replace "**" "\\**" (String.concat children) ++ "**"

        Emphasis children ->
            "_" ++ escape "_" (String.concat children) ++ "_"

        Strikethrough children ->
            "~" ++ escape "~" (String.concat children) ++ "~"

        CodeSpan content ->
            "`" ++ content ++ "`"

        Link { destination, children } ->
            "[" ++ escape "]" (escape ")" (String.concat children)) ++ "](" ++ destination ++ ")"

        Image { alt, src, title } ->
            "!["
                ++ escape "]" (escape ")" alt)
                ++ "]("
                ++ src
                ++ (title
                        |> Maybe.map (\t -> " \"" ++ escape "\"" t ++ "\"")
                        |> Maybe.withDefault ""
                   )
                ++ ")"

        UnorderedList { items } ->
            items
                |> List.map
                    (\(Block.ListItem task children) ->
                        case task of
                            Block.NoTask ->
                                "- " ++ String.concat children

                            Block.IncompleteTask ->
                                "- [ ] " ++ String.concat children

                            Block.CompletedTask ->
                                "- [X] " ++ String.concat children
                    )
                |> String.join "\n"

        OrderedList { startingIndex, items } ->
            items
                |> List.indexedMap
                    (\index children ->
                        String.fromInt (index + startingIndex)
                            ++ ". "
                            ++ String.concat children
                    )
                |> String.join "\n"

        CodeBlock { body, language } ->
            case language of
                Just langName ->
                    "```"
                        ++ langName
                        ++ "\n"
                        ++ body
                        ++ "```"

                Nothing ->
                    let
                        bodyLines =
                            body
                                |> String.split "\n"
                    in
                    if bodyLines |> List.any (not << String.startsWith " ") then
                        bodyLines
                            |> List.map ((++) "    ")
                            |> String.join "\n"

                    else
                        "```\n" ++ body ++ "```"

        HardLineBreak ->
            "\n\n"

        ThematicBreak ->
            "---\n"

        -- For table pretty-printing support, take a look at the Markdown.PrettyTables module
        Table children ->
            ""

        TableHeader children ->
            ""

        TableBody children ->
            ""

        TableRow children ->
            ""

        TableCell align children ->
            ""

        TableHeaderCell align children ->
            ""


{-| Reduces a block down to anything that can be accumulated.

You provide two functions

  - `accumulate`: Describe how values of type `a` are combined. Examples: `List.concat`,
    `List.sum`, etc.
  - `extract`: Descibe how a blocks generate values that are supposed to be accumulated.

For example, this can count the amount of headings in a markdown document:

    reduce
        { accumulate = List.sum
        , extract =
            \block ->
                case block of
                    Heading _ ->
                        1

                    _ ->
                        0
        }

Or this extracts code blocks:

    reduce
        { accumulate = List.concat
        , extract =
            \block ->
                case block of
                    CodeBlock codeBlock ->
                        [ codeBlock ]

                    _ ->
                        []
        }

The special thing about this function is how you don't have to worry about accumulating
the other generated values recursively.

-}
reduce : { accumulate : List a -> a, extract : Block a -> a } -> Block a -> a
reduce { extract, accumulate } block =
    let
        append a b =
            accumulate [ a, b ]
    in
    case block of
        Heading { children } ->
            accumulate children
                |> append (extract block)

        Paragraph children ->
            accumulate children
                |> append (extract block)

        BlockQuote children ->
            accumulate children
                |> append (extract block)

        Text _ ->
            extract block

        CodeSpan _ ->
            extract block

        Strong children ->
            accumulate children
                |> append (extract block)

        Emphasis children ->
            accumulate children
                |> append (extract block)

        Strikethrough children ->
            accumulate children
                |> append (extract block)

        Link link ->
            accumulate link.children
                |> append (extract block)

        Image _ ->
            extract block

        UnorderedList { items } ->
            items
                |> List.concatMap
                    (\(Block.ListItem _ child) -> child)
                |> accumulate
                |> append (extract block)

        OrderedList { items } ->
            items
                |> List.concat
                |> accumulate
                |> append (extract block)

        CodeBlock _ ->
            extract block

        HardLineBreak ->
            extract block

        ThematicBreak ->
            extract block

        Table children ->
            accumulate children
                |> append (extract block)

        TableHeader children ->
            accumulate children
                |> append (extract block)

        TableBody children ->
            accumulate children
                |> append (extract block)

        TableRow children ->
            accumulate children
                |> append (extract block)

        TableHeaderCell _ children ->
            accumulate children
                |> append (extract block)

        TableCell _ children ->
            accumulate children
                |> append (extract block)


{-| There are two ways of thinking about this function:

1.  Render a `Block` using the given elm-markdown `Renderer`.
2.  Extract a function of type `(Block view -> view)` out of
    the elm-markdown `Renderer`. This is useful if you want to make use
    of the utilities present in this library.

-}
fromRenderer : Renderer view -> Block view -> view
fromRenderer renderer markdown =
    case markdown of
        Heading info ->
            renderer.heading info

        Paragraph children ->
            renderer.paragraph children

        BlockQuote children ->
            renderer.blockQuote children

        Text content ->
            renderer.text content

        CodeSpan content ->
            renderer.codeSpan content

        Strong children ->
            renderer.strong children

        Emphasis children ->
            renderer.emphasis children

        Strikethrough children ->
            renderer.strikethrough children

        Link { title, destination, children } ->
            renderer.link { title = title, destination = destination } children

        Image imageInfo ->
            renderer.image imageInfo

        UnorderedList { items } ->
            renderer.unorderedList items

        OrderedList { startingIndex, items } ->
            renderer.orderedList startingIndex items

        CodeBlock info ->
            renderer.codeBlock info

        HardLineBreak ->
            renderer.hardLineBreak

        ThematicBreak ->
            renderer.thematicBreak

        Table children ->
            renderer.table children

        TableHeader children ->
            renderer.tableHeader children

        TableBody children ->
            renderer.tableBody children

        TableRow children ->
            renderer.tableRow children

        TableHeaderCell maybeAlignment children ->
            renderer.tableHeaderCell maybeAlignment children

        TableCell maybeAlignment children ->
            renderer.tableCell maybeAlignment children


{-| Convert a function that works with `Block` to a `Renderer` for use with
elm-markdown.

(The second parameter is a [`Markdown.Html.Renderer`](/packages/dillonkearns/elm-markdown/3.0.0/Markdown-Html#Renderer))

-}
toRenderer :
    { renderMarkdown : Block view -> view
    , renderHtml : Markdown.Html.Renderer (List view -> view)
    }
    -> Renderer view
toRenderer { renderMarkdown, renderHtml } =
    { heading = Heading >> renderMarkdown
    , paragraph = Paragraph >> renderMarkdown
    , blockQuote = BlockQuote >> renderMarkdown
    , html = renderHtml
    , text = Text >> renderMarkdown
    , codeSpan = CodeSpan >> renderMarkdown
    , strong = Strong >> renderMarkdown
    , emphasis = Emphasis >> renderMarkdown
    , strikethrough = Emphasis >> renderMarkdown
    , hardLineBreak = HardLineBreak |> renderMarkdown
    , link =
        \{ title, destination } children ->
            Link { title = title, destination = destination, children = children }
                |> renderMarkdown
    , image = Image >> renderMarkdown
    , unorderedList =
        \items ->
            UnorderedList { items = items }
                |> renderMarkdown
    , orderedList =
        \startingIndex items ->
            OrderedList { startingIndex = startingIndex, items = items }
                |> renderMarkdown
    , codeBlock = CodeBlock >> renderMarkdown
    , thematicBreak = ThematicBreak |> renderMarkdown
    , table = Table >> renderMarkdown
    , tableHeader = TableHeader >> renderMarkdown
    , tableBody = TableBody >> renderMarkdown
    , tableRow = TableRow >> renderMarkdown
    , tableHeaderCell = \maybeAlignment -> TableHeaderCell maybeAlignment >> renderMarkdown
    , tableCell = \maybeAlignment -> TableCell maybeAlignment >> renderMarkdown
    }


{-| Bump all `Heading` elements by given positive amount of levels.

    import Markdown.Block as Block

    bumpHeadings 2
        (Heading
            { level = Block.H1
            , rawText = ""
            , children = []
            }
        )
    --> Heading
    -->     { level = Block.H3
    -->     , rawText = ""
    -->     , children = []
    -->     }

    bumpHeadings 1
        (Heading
            { level = Block.H6
            , rawText = ""
            , children = []
            }
        )
    --> Heading
    -->     { level = Block.H6
    -->     , rawText = ""
    -->     , children = []
    -->     }

    bumpHeadings -1
        (Heading
            { level = Block.H2
            , rawText = ""
            , children = []
            }
        )
    --> Heading
    -->     { level = Block.H2
    -->     , rawText = ""
    -->     , children = []
    -->     }

-}
bumpHeadings : Int -> Block view -> Block view
bumpHeadings by markdown =
    let
        -- vendored from elm-loop
        for : Int -> (a -> a) -> a -> a
        for =
            let
                for_ : Int -> Int -> (a -> a) -> a -> a
                for_ i n f v =
                    if i < n then
                        for_ (i + 1) n f (f v)

                    else
                        v
            in
            for_ 0
    in
    case markdown of
        Heading info ->
            Heading { info | level = for by bumpHeadingLevel info.level }

        other ->
            other



-- LOCAL DEFINITIONS


allStaticHttp : List (BackendTask a) -> BackendTask (List a)
allStaticHttp =
    List.foldr (BackendTask.map2 (::)) (BackendTask.succeed [])


bumpHeadingLevel : Block.HeadingLevel -> Block.HeadingLevel
bumpHeadingLevel level =
    case level of
        Block.H1 ->
            Block.H2

        Block.H2 ->
            Block.H3

        Block.H3 ->
            Block.H4

        Block.H4 ->
            Block.H5

        Block.H5 ->
            Block.H6

        Block.H6 ->
            Block.H6
