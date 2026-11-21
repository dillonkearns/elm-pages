module PageUrlTest exposing (all)

import Dict
import Expect
import Pages.PageUrl exposing (PageUrl)
import Test exposing (Test, describe, test)
import Url
import UrlPath


all : Test
all =
    describe "PageUrl"
        [ describe "toUrl"
            [ test "path has leading slash" <|
                \() ->
                    { protocol = Url.Https
                    , host = "example.com"
                    , port_ = Nothing
                    , path = UrlPath.join [ "blog", "post-1" ]
                    , query = Dict.empty
                    , fragment = Nothing
                    }
                        |> Pages.PageUrl.toUrl
                        |> .path
                        |> Expect.equal "/blog/post-1"
            , test "path has leading slash with base path prefix" <|
                \() ->
                    { protocol = Url.Https
                    , host = "example.com"
                    , port_ = Nothing
                    , path = UrlPath.join [ "prefix", "page" ]
                    , query = Dict.empty
                    , fragment = Nothing
                    }
                        |> Pages.PageUrl.toUrl
                        |> .path
                        |> Expect.equal "/prefix/page"
            , test "Url.toString produces correct URL with base path" <|
                \() ->
                    { protocol = Url.Https
                    , host = "example.com"
                    , port_ = Nothing
                    , path = UrlPath.join [ "prefix" ]
                    , query = Dict.empty
                    , fragment = Nothing
                    }
                        |> Pages.PageUrl.toUrl
                        |> Url.toString
                        |> Expect.equal "https://example.com/prefix"
            , test "root path produces slash" <|
                \() ->
                    { protocol = Url.Https
                    , host = "example.com"
                    , port_ = Nothing
                    , path = UrlPath.join []
                    , query = Dict.empty
                    , fragment = Nothing
                    }
                        |> Pages.PageUrl.toUrl
                        |> Url.toString
                        |> Expect.equal "https://example.com/"
            , test "query params are preserved" <|
                \() ->
                    { protocol = Url.Https
                    , host = "example.com"
                    , port_ = Nothing
                    , path = UrlPath.join [ "search" ]
                    , query = Dict.fromList [ ( "q", [ "elm" ] ) ]
                    , fragment = Nothing
                    }
                        |> Pages.PageUrl.toUrl
                        |> Url.toString
                        |> String.contains "q=elm"
                        |> Expect.equal True
            , test "fragment is preserved" <|
                \() ->
                    { protocol = Url.Https
                    , host = "example.com"
                    , port_ = Nothing
                    , path = UrlPath.join [ "docs" ]
                    , query = Dict.empty
                    , fragment = Just "section-1"
                    }
                        |> Pages.PageUrl.toUrl
                        |> .fragment
                        |> Expect.equal (Just "section-1")
            ]
        ]
