module Pages.Review.DeadCodeEliminateDataTest exposing (all)

import Pages.Review.DeadCodeEliminateData exposing (rule)
import Review.Test
import Test exposing (Test, describe, test)


all : Test
all =
    describe "dead code elimination"
        [ test "replaces head record setter" <|
            \() ->
                """module Route.Index exposing (Data, Model, Msg, route)

import Server.Request as Request

import BackendTask exposing (BackendTask)
import FatalError
import RouteBuilder exposing (Page, App, single)
import Pages.PageUrl exposing (PageUrl)
import Pages.Url
import UrlPath
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
       , data = BackendTask.fail (FatalError.fromString "")
       }
       |> RouteBuilder.buildNoState { view = view }


head : App Data ActionData RouteParams -> List Head.Tag
head app =
    []
"""
                    |> Review.Test.run rule
                    |> Review.Test.expectErrors
                        [ Review.Test.error
                            { message = "Codemod"
                            , details =
                                [ "" ]
                            , under =
                                """head = head"""
                            }
                            |> Review.Test.whenFixed
                                """module Route.Index exposing (Data, Model, Msg, route)

import Server.Request as Request

import BackendTask exposing (BackendTask)
import FatalError
import RouteBuilder exposing (Page, App, single)
import Pages.PageUrl exposing (PageUrl)
import Pages.Url
import UrlPath
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
       { head = \\_ -> []
       , data = BackendTask.fail (FatalError.fromString "")
       }
       |> RouteBuilder.buildNoState { view = view }


head : App Data ActionData RouteParams -> List Head.Tag
head app =
    []
"""
                        ]
        , test "replaces data record setter" <|
            \() ->
                """module Route.Index exposing (Data, Model, Msg, route)

import Server.Request as Request

import BackendTask exposing (BackendTask)
import FatalError
import RouteBuilder exposing (Page, App, single)
import Pages.PageUrl exposing (PageUrl)
import Pages.Url
import UrlPath
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
       { head = \\_ -> []
       , data = data
       }
       |> RouteBuilder.buildNoState { view = view }


data : BackendTask Data
data =
    BackendTask.succeed ()
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

import BackendTask exposing (BackendTask)
import FatalError
import RouteBuilder exposing (Page, App, single)
import Pages.PageUrl exposing (PageUrl)
import Pages.Url
import UrlPath
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
       { head = \\_ -> []
       , data = BackendTask.fail (FatalError.fromString "")
       }
       |> RouteBuilder.buildNoState { view = view }


data : BackendTask Data
data =
    BackendTask.succeed ()
"""
                        ]
        , test "replaces import with exposing line" <|
            \() ->
                """module View exposing (View, map, placeholder)

import Html.Styled as Html exposing (Html)


type alias View msg =
   { title : String
   , body : List (Html msg)
   }


map : (msg1 -> msg2) -> View msg1 -> View msg2
map fn view =
   { title = view.title
   , body = List.map (Html.map fn) view.body
   }


placeholder : String -> View msg
placeholder moduleName =
   { title = "Placeholder"
   , body = [ Html.text moduleName ]
   }
"""
                    |> Review.Test.run rule
                    |> Review.Test.expectErrors
                        [ Review.Test.error
                            { message = "Codemod"
                            , details =
                                [ "" ]
                            , under =
                                """import Html.Styled as Html exposing (Html)"""
                            }
                            |> Review.Test.whenFixed
                                """module View exposing (View, map, placeholder)


import FatalError
import Html.Styled as Html exposing (Html)


type alias View msg =
   { title : String
   , body : List (Html msg)
   }


map : (msg1 -> msg2) -> View msg1 -> View msg2
map fn view =
   { title = view.title
   , body = List.map (Html.map fn) view.body
   }


placeholder : String -> View msg
placeholder moduleName =
   { title = "Placeholder"
   , body = [ Html.text moduleName ]
   }
"""
                        ]
        , test "supports aliased BackendTask module import" <|
            \() ->
                """module Route.Index exposing (Data, Model, Msg, route)

import Server.Request as Request
import FatalError
import BackendTask as DS
import RouteBuilder exposing (Page, App, single)
import Pages.PageUrl exposing (PageUrl)
import Pages.Url
import UrlPath
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
       { head = \\_ -> []
       , data = data
       }
       |> RouteBuilder.buildNoState { view = view }


data : BackendTask Data
data =
    BackendTask.succeed ()
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
import FatalError
import BackendTask as DS
import RouteBuilder exposing (Page, App, single)
import Pages.PageUrl exposing (PageUrl)
import Pages.Url
import UrlPath
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
       { head = \\_ -> []
       , data = DS.fail (FatalError.fromString "")
       }
       |> RouteBuilder.buildNoState { view = view }


data : BackendTask Data
data =
    BackendTask.succeed ()
"""
                        ]
        , test "replaces data record setter with non-empty RouteParams" <|
            \() ->
                """module Route.Blog.Slug_ exposing (Data, Model, Msg, route)

import Server.Request as Request

import BackendTask exposing (BackendTask)
import FatalError
import RouteBuilder exposing (Page, App)
import Pages.PageUrl exposing (PageUrl)
import Pages.Url
import UrlPath
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
        , head = \\_ -> []
        , pages = BackendTask.fail (FatalError.fromString "")
        }
        |> RouteBuilder.buildNoState { view = view }


data : BackendTask Data
data =
    BackendTask.succeed ()
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

import BackendTask exposing (BackendTask)
import FatalError
import RouteBuilder exposing (Page, App)
import Pages.PageUrl exposing (PageUrl)
import Pages.Url
import UrlPath
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
        { data = \\_ -> BackendTask.fail (FatalError.fromString "")
        , head = \\_ -> []
        , pages = BackendTask.fail (FatalError.fromString "")
        }
        |> RouteBuilder.buildNoState { view = view }


data : BackendTask Data
data =
    BackendTask.succeed ()
"""
                        ]
        , test "replaces pages record setter in preRender" <|
            \() ->
                """module Route.Blog.Slug_ exposing (Data, Model, Msg, route)

import Server.Request as Request

import BackendTask exposing (BackendTask)
import FatalError
import RouteBuilder exposing (Page, App)
import Pages.PageUrl exposing (PageUrl)
import Pages.Url
import UrlPath
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
        { data = \\_ -> BackendTask.fail (FatalError.fromString "")
        , head = \\_ -> []
        , pages = pages
        }
        |> RouteBuilder.buildNoState { view = view }


pages : BackendTask (List RouteParams)
pages =
    BackendTask.succeed [ { slug = "hello" } ]
"""
                    |> Review.Test.run rule
                    |> Review.Test.expectErrors
                        [ Review.Test.error
                            { message = "Codemod"
                            , details =
                                [ "" ]
                            , under =
                                """pages = pages
        }"""
                            }
                            |> Review.Test.whenFixed
                                """module Route.Blog.Slug_ exposing (Data, Model, Msg, route)

import Server.Request as Request

import BackendTask exposing (BackendTask)
import FatalError
import RouteBuilder exposing (Page, App)
import Pages.PageUrl exposing (PageUrl)
import Pages.Url
import UrlPath
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
        { data = \\_ -> BackendTask.fail (FatalError.fromString "")
        , head = \\_ -> []
        , pages = BackendTask.fail (FatalError.fromString "")}
        |> RouteBuilder.buildNoState { view = view }


pages : BackendTask (List RouteParams)
pages =
    BackendTask.succeed [ { slug = "hello" } ]
"""
                        ]
        , test "replaces data record setter with RouteBuilder.serverRendered" <|
            \() ->
                """module Route.Login exposing (Data, Model, Msg, route)

import Server.Request as Request
import FatalError

type alias Model =
    {}


type alias Msg =
    ()


type alias RouteParams =
    {}


route : StatelessRoute RouteParams Data ActionData
route =
    RouteBuilder.serverRender
        { head = \\_ -> []
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
import FatalError

type alias Model =
    {}


type alias Msg =
    ()


type alias RouteParams =
    {}


route : StatelessRoute RouteParams Data ActionData
route =
    RouteBuilder.serverRender
        { head = \\_ -> []
        , data = \\_ _ -> BackendTask.fail (FatalError.fromString "")
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
import FatalError

type alias Model =
    {}


type alias Msg =
    ()


type alias RouteParams =
    {}


route : StatelessRoute RouteParams Data ActionData
route =
    RouteBuilder.serverRender
        { head = \\_ -> []
        , data = data
        , action = \\_ _ -> BackendTask.fail (FatalError.fromString "")
        }
        |> RouteBuilder.buildNoState { view = view }
"""
                        ]
        , test "uses appropriate import alias for Server.Request module" <|
            \() ->
                """module Route.Login exposing (Data, Model, Msg, route)

import Server.Request
import FatalError

type alias Model =
    {}


type alias Msg =
    ()


type alias RouteParams =
    {}


route : StatelessRoute RouteParams Data ActionData
route =
    RouteBuilder.serverRender
        { head = \\_ -> []
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
import FatalError

type alias Model =
    {}


type alias Msg =
    ()


type alias RouteParams =
    {}


route : StatelessRoute RouteParams Data ActionData
route =
    RouteBuilder.serverRender
        { head = \\_ -> []
        , data = \\_ _ -> BackendTask.fail (FatalError.fromString "")
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
import FatalError

type alias Model =
    {}


type alias Msg =
    ()


type alias RouteParams =
    {}


route : StatelessRoute RouteParams Data ActionData
route =
    RouteBuilder.serverRender
        { head = \\_ -> []
        , data = data
        , action = \\_ _ -> BackendTask.fail (FatalError.fromString "")
        }
        |> RouteBuilder.buildNoState { view = view }
"""
                        ]
        , test "no Request.oneOf fix after replacement is made" <|
            \() ->
                """module Route.Login exposing (Data, Model, Msg, route)

import Server.Request as Request
import FatalError

type alias Model =
    {}


type alias Msg =
    ()


type alias RouteParams =
    {}


route : StatelessRoute RouteParams Data ActionData
route =
    RouteBuilder.serverRender
        { head = \\_ -> []
        , data = \\_ _ -> BackendTask.fail (FatalError.fromString "")
        }
        |> RouteBuilder.buildNoState { view = view }
"""
                    |> Review.Test.run rule
                    |> Review.Test.expectNoErrors
        , test "no fix after replacement is made" <|
            \() ->
                """module Route.Index exposing (Data, Model, Msg, route)

import Server.Request as Request
import FatalError

import BackendTask exposing (BackendTask)
import RouteBuilder exposing (Page, App)
import Pages.PageUrl exposing (PageUrl)
import Pages.Url
import UrlPath
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
       { head = \\_ -> []
       , data = BackendTask.fail (FatalError.fromString "")
       }
       |> RouteBuilder.buildNoState { view = view }


data : BackendTask Data
data =
    BackendTask.succeed ()
"""
                    |> Review.Test.run rule
                    |> Review.Test.expectNoErrors
        , test "replaces data record setter in Shared module" <|
            \() ->
                """module Shared exposing (Data, Model, Msg, template)

import Server.Request as Request
import FatalError

import Browser.Navigation
import BackendTask
import Html exposing (Html)
import Html.Styled
import Pages.Flags
import Pages.PageUrl exposing (PageUrl)
import UrlPath exposing (UrlPath)
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
import FatalError

import Browser.Navigation
import BackendTask
import Html exposing (Html)
import Html.Styled
import Pages.Flags
import Pages.PageUrl exposing (PageUrl)
import UrlPath exposing (UrlPath)
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
    , data = BackendTask.fail (FatalError.fromString "")
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
