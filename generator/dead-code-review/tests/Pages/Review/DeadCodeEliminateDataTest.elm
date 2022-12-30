module Pages.Review.DeadCodeEliminateDataTest exposing (all)

import Pages.Review.DeadCodeEliminateData exposing (rule)
import Review.Test
import Test exposing (Test, describe, test)


all : Test
all =
    describe "dead code elimination"
        [ test "replaces data record setter" <|
            \() ->
                """module Route.Index exposing (Data, Model, Msg, route)

import Server.Request as Request

import DataSource exposing (DataSource)
import RouteBuilder exposing (Page, StaticPayload, single)
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


route : StatelessRoute RouteParams Data ActionData
route =
   single
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
                                """module Route.Index exposing (Data, Model, Msg, route)

import Server.Request as Request

import DataSource exposing (DataSource)
import RouteBuilder exposing (Page, StaticPayload, single)
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


route : StatelessRoute RouteParams Data ActionData
route =
   single
       { head = head
       , data = DataSource.fail (Exception.fromString "")
       }
       |> RouteBuilder.buildNoState { view = view }


data : DataSource Data
data =
    DataSource.succeed ()
"""
                        ]
        , test "supports aliased DataSource module import" <|
            \() ->
                """module Route.Index exposing (Data, Model, Msg, route)

import Server.Request as Request
import DataSource as DS
import RouteBuilder exposing (Page, StaticPayload, single)
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


route : StatelessRoute RouteParams Data ActionData
route =
   single
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
                                """module Route.Index exposing (Data, Model, Msg, route)

import Server.Request as Request
import DataSource as DS
import RouteBuilder exposing (Page, StaticPayload, single)
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


route : StatelessRoute RouteParams Data ActionData
route =
   single
       { head = head
       , data = DS.fail (Exception.fromString "")
       }
       |> RouteBuilder.buildNoState { view = view }


data : DataSource Data
data =
    DataSource.succeed ()
"""
                        ]
        , test "replaces data record setter with non-empty RouteParams" <|
            \() ->
                """module Route.Blog.Slug_ exposing (Data, Model, Msg, route)

import Server.Request as Request

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


route : StatelessRoute RouteParams Data ActionData
route =
    RouteBuilder.preRender
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
                                """module Route.Blog.Slug_ exposing (Data, Model, Msg, route)

import Server.Request as Request

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


route : StatelessRoute RouteParams Data ActionData
route =
    RouteBuilder.preRender
        { data = \\_ -> DataSource.fail (Exception.fromString "")
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
                """module Route.Login exposing (Data, Model, Msg, route)

import Server.Request as Request

type alias Model =
    {}


type alias Msg =
    ()


type alias RouteParams =
    {}


route : StatelessRoute RouteParams Data ActionData
route =
    RouteBuilder.serverRender
        { head = head
        , data = data
        , action = action
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
        ,"""
                            }
                            |> Review.Test.whenFixed
                                """module Route.Login exposing (Data, Model, Msg, route)

import Server.Request as Request

type alias Model =
    {}


type alias Msg =
    ()


type alias RouteParams =
    {}


route : StatelessRoute RouteParams Data ActionData
route =
    RouteBuilder.serverRender
        { head = head
        , data = \\_ -> Request.oneOf []
        , action = action
        }
        |> RouteBuilder.buildNoState { view = view }
"""
                        , Review.Test.error
                            { message = "Codemod"
                            , details =
                                [ "" ]
                            , under =
                                """action = action
        }"""
                            }
                            |> Review.Test.whenFixed
                                """module Route.Login exposing (Data, Model, Msg, route)

import Server.Request as Request

type alias Model =
    {}


type alias Msg =
    ()


type alias RouteParams =
    {}


route : StatelessRoute RouteParams Data ActionData
route =
    RouteBuilder.serverRender
        { head = head
        , data = data
        , action = \\_ -> Request.oneOf []
        }
        |> RouteBuilder.buildNoState { view = view }
"""
                        ]
        , test "uses appropriate import alias for Server.Request module" <|
            \() ->
                """module Route.Login exposing (Data, Model, Msg, route)

import Server.Request

type alias Model =
    {}


type alias Msg =
    ()


type alias RouteParams =
    {}


route : StatelessRoute RouteParams Data ActionData
route =
    RouteBuilder.serverRender
        { head = head
        , data = data
        , action = action
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
        ,"""
                            }
                            |> Review.Test.whenFixed
                                """module Route.Login exposing (Data, Model, Msg, route)

import Server.Request

type alias Model =
    {}


type alias Msg =
    ()


type alias RouteParams =
    {}


route : StatelessRoute RouteParams Data ActionData
route =
    RouteBuilder.serverRender
        { head = head
        , data = \\_ -> Server.Request.oneOf []
        , action = action
        }
        |> RouteBuilder.buildNoState { view = view }
"""
                        , Review.Test.error
                            { message = "Codemod"
                            , details =
                                [ "" ]
                            , under =
                                """action = action
        }"""
                            }
                            |> Review.Test.whenFixed
                                """module Route.Login exposing (Data, Model, Msg, route)

import Server.Request

type alias Model =
    {}


type alias Msg =
    ()


type alias RouteParams =
    {}


route : StatelessRoute RouteParams Data ActionData
route =
    RouteBuilder.serverRender
        { head = head
        , data = data
        , action = \\_ -> Server.Request.oneOf []
        }
        |> RouteBuilder.buildNoState { view = view }
"""
                        ]
        , test "no Request.oneOf fix after replacement is made" <|
            \() ->
                """module Route.Login exposing (Data, Model, Msg, route)

import Server.Request as Request

type alias Model =
    {}


type alias Msg =
    ()


type alias RouteParams =
    {}


route : StatelessRoute RouteParams Data ActionData
route =
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
                """module Route.Index exposing (Data, Model, Msg, route)

import Server.Request as Request

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


route : StatelessRoute RouteParams Data ActionData
route =
   RouteBuilder.single
       { head = head
       , data = DataSource.fail (Exception.fromString "")
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

import Server.Request as Request

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

import Server.Request as Request

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
    , data = DataSource.fail (Exception.fromString "")
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
