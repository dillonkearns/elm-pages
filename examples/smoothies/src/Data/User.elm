module Data.User exposing (User, userSelection)

import Api.InputObject
import Api.Mutation
import Api.Object.Order
import Api.Object.Order_item
import Api.Object.Products
import Api.Object.Users
import Api.Query
import Api.Scalar exposing (Uuid(..))
import Data.Cart as Cart exposing (Cart)
import DataSource exposing (DataSource)
import Dict exposing (Dict)
import Effect exposing (Effect)
import ErrorPage exposing (ErrorPage)
import Graphql.Operation exposing (RootQuery)
import Graphql.OptionalArgument exposing (OptionalArgument(..))
import Graphql.SelectionSet as SelectionSet exposing (SelectionSet)
import Head
import Head.Seo as Seo
import Html exposing (Html)
import Html.Attributes as Attr
import Icon
import MySession
import Pages.Msg
import Pages.PageUrl exposing (PageUrl)
import Pages.Url
import Path exposing (Path)
import Request.Hasura
import Route
import RouteBuilder exposing (StatefulRoute, StatelessRoute, StaticPayload)
import Seo.Common
import Server.Request as Request
import Server.Response as Response exposing (Response)
import Server.Session as Session
import Shared
import Time
import View exposing (View)


type alias User =
    { name : String }


userSelection : String -> SelectionSet User RootQuery
userSelection userId =
    Api.Query.users_by_pk { id = Uuid userId }
        (SelectionSet.map User Api.Object.Users.name)
        |> SelectionSet.nonNullOrFail
