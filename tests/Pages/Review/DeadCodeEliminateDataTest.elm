module Pages.Review.DeadCodeEliminateDataTest exposing (all)

import Pages.Review.DeadCodeEliminateData exposing (rule)
import Review.Test
import Test exposing (Test, describe, test)


all : Test
all =
    describe "dead code elimination"
        [ test "replaces data record setter" <|
            \() ->
                """module Page.Index exposing (Data, Model, Msg, page)

import DataSource exposing (DataSource)
import RouteBuilder exposing (Page, StaticPayload)
import Pages.PageUrl exposing (PageUrl)
import Pages.Url
import Path
import Route exposing (Route)
import Shared
import View exposing (View)


type alias Model =
   {}


type alias Msg =
   ()


type alias RouteParams =
   {}


type alias Data =
   ()


page : StatelessRoute RouteParams Data
page =
   RouteBuilder.single
       { head = head
       , data = data
       }
       |> RouteBuilder.buildNoState { view = view }


data : DataSource Data
data =
    DataSource.succeed ()
"""
                    |> Review.Test.run rule
                    |> Review.Test.expectErrors
                        [ Review.Test.error
                            { message = "Codemod"
                            , details =
                                [ "" ]
                            , under =
                                """data = data
       }"""
                            }
                            |> Review.Test.whenFixed
                                """module Page.Index exposing (Data, Model, Msg, page)

import DataSource exposing (DataSource)
import RouteBuilder exposing (Page, StaticPayload)
import Pages.PageUrl exposing (PageUrl)
import Pages.Url
import Path
import Route exposing (Route)
import Shared
import View exposing (View)


type alias Model =
   {}


type alias Msg =
   ()


type alias RouteParams =
   {}


type alias Data =
   ()


page : StatelessRoute RouteParams Data
page =
   RouteBuilder.single
       { head = head
       , data = DataSource.fail ""
       }
       |> RouteBuilder.buildNoState { view = view }


data : DataSource Data
data =
    DataSource.succeed ()
"""
                        ]
        , test "replaces data record setter with non-empty RouteParams" <|
            \() ->
                """module Page.Blog.Slug_ exposing (Data, Model, Msg, page)

import DataSource exposing (DataSource)
import RouteBuilder exposing (Page, StaticPayload)
import Pages.PageUrl exposing (PageUrl)
import Pages.Url
import Path
import Route exposing (Route)
import Shared
import View exposing (View)


type alias Model =
   {}


type alias Msg =
   ()


type alias RouteParams =
    { slug : String }


type alias Data =
   ()


page : StatelessRoute RouteParams Data
page =
    Page.preRender
        { data = data
        , head = head
        , pages = pages
        }
        |> RouteBuilder.buildNoState { view = view }


data : DataSource Data
data =
    DataSource.succeed ()
"""
                    |> Review.Test.run rule
                    |> Review.Test.expectErrors
                        [ Review.Test.error
                            { message = "Codemod"
                            , details =
                                [ "" ]
                            , under =
                                """data = data"""
                            }
                            |> Review.Test.whenFixed
                                """module Page.Blog.Slug_ exposing (Data, Model, Msg, page)

import DataSource exposing (DataSource)
import RouteBuilder exposing (Page, StaticPayload)
import Pages.PageUrl exposing (PageUrl)
import Pages.Url
import Path
import Route exposing (Route)
import Shared
import View exposing (View)


type alias Model =
   {}


type alias Msg =
   ()


type alias RouteParams =
    { slug : String }


type alias Data =
   ()


page : StatelessRoute RouteParams Data
page =
    Page.preRender
        { data = \\_ -> DataSource.fail ""
        , head = head
        , pages = pages
        }
        |> RouteBuilder.buildNoState { view = view }


data : DataSource Data
data =
    DataSource.succeed ()
"""
                        ]
        , test "replaces data record setter with RouteBuilder.serverRendered" <|
            \() ->
                """module Page.Login exposing (Data, Model, Msg, page)

type alias Model =
    {}


type alias Msg =
    ()


type alias RouteParams =
    {}


page : StatelessRoute RouteParams Data
page =
    RouteBuilder.serverRender
        { head = head
        , data = data
        }
        |> RouteBuilder.buildNoState { view = view }
"""
                    |> Review.Test.run rule
                    |> Review.Test.expectErrors
                        [ Review.Test.error
                            { message = "Codemod"
                            , details =
                                [ "" ]
                            , under =
                                """data = data
        }"""
                            }
                            |> Review.Test.whenFixed
                                """module Page.Login exposing (Data, Model, Msg, page)

type alias Model =
    {}


type alias Msg =
    ()


type alias RouteParams =
    {}


page : StatelessRoute RouteParams Data
page =
    RouteBuilder.serverRender
        { head = head
        , data = \\_ -> Request.oneOf []
        }
        |> RouteBuilder.buildNoState { view = view }
"""
                        ]
        , test "no Request.oneOf fix after replacement is made" <|
            \() ->
                """module Page.Login exposing (Data, Model, Msg, page)

type alias Model =
    {}


type alias Msg =
    ()


type alias RouteParams =
    {}


page : StatelessRoute RouteParams Data
page =
    RouteBuilder.serverRender
        { head = head
        , data = \\_ -> Request.oneOf []
        }
        |> RouteBuilder.buildNoState { view = view }
"""
                    |> Review.Test.run rule
                    |> Review.Test.expectNoErrors
        , test "no fix after replacement is made" <|
            \() ->
                """module Page.Index exposing (Data, Model, Msg, page)

import DataSource exposing (DataSource)
import RouteBuilder exposing (Page, StaticPayload)
import Pages.PageUrl exposing (PageUrl)
import Pages.Url
import Path
import Route exposing (Route)
import Shared
import View exposing (View)


type alias Model =
   {}


type alias Msg =
   ()


type alias RouteParams =
   {}


type alias Data =
   ()


page : StatelessRoute RouteParams Data
page =
   RouteBuilder.single
       { head = head
       , data = DataSource.fail ""
       }
       |> RouteBuilder.buildNoState { view = view }


data : DataSource Data
data =
    DataSource.succeed ()
"""
                    |> Review.Test.run rule
                    |> Review.Test.expectNoErrors
        , test "replaces data record setter in Shared module" <|
            \() ->
                """module Shared exposing (Data, Model, Msg, template)

import Browser.Navigation
import DataSource
import Html exposing (Html)
import Html.Styled
import Pages.Flags
import Pages.PageUrl exposing (PageUrl)
import Path exposing (Path)
import Route exposing (Route)
import SharedTemplate exposing (SharedTemplate)
import TableOfContents
import View exposing (View)
import View.Header


template : SharedTemplate Msg Model Data msg
template =
    { init = init
    , update = update
    , view = view
    , data = data
    , subscriptions = subscriptions
    , onPageChange = Just OnPageChange
    }


type alias Data =
    TableOfContents.TableOfContents TableOfContents.Data


type alias Model =
    { showMobileMenu : Bool
    , counter : Int
    , navigationKey : Maybe Browser.Navigation.Key
    }
"""
                    |> Review.Test.run rule
                    |> Review.Test.expectErrors
                        [ Review.Test.error
                            { message = "Codemod"
                            , details =
                                [ "" ]
                            , under =
                                """data = data
    ,"""
                            }
                            |> Review.Test.whenFixed
                                """module Shared exposing (Data, Model, Msg, template)

import Browser.Navigation
import DataSource
import Html exposing (Html)
import Html.Styled
import Pages.Flags
import Pages.PageUrl exposing (PageUrl)
import Path exposing (Path)
import Route exposing (Route)
import SharedTemplate exposing (SharedTemplate)
import TableOfContents
import View exposing (View)
import View.Header


template : SharedTemplate Msg Model Data msg
template =
    { init = init
    , update = update
    , view = view
    , data = DataSource.fail ""
    , subscriptions = subscriptions
    , onPageChange = Just OnPageChange
    }


type alias Data =
    TableOfContents.TableOfContents TableOfContents.Data


type alias Model =
    { showMobileMenu : Bool
    , counter : Int
    , navigationKey : Maybe Browser.Navigation.Key
    }
"""
                        ]
        ]
