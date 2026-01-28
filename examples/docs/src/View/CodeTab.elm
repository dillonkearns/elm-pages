module View.CodeTab exposing (view)

import Html exposing (..)
import Html.Attributes as Attr
import SyntaxHighlight


view : ( String, String ) -> Html msg
view tab =
    div
        [ Attr.class "rounded-xl shadow-2xl bg-black rounded-lg shadow-lg"
        ]
        [ iconArea
        , codeTabs tab
        , elmCodeBlock (Tuple.second tab)
        ]


iconArea : Html msg
iconArea =
    div
        [ Attr.class "flex-none items-center flex h-11 px-4"
        ]
        [ div
            [ Attr.class "flex space-x-1.5" ]
            [ div
                [ Attr.class "w-3 h-3 border-2 rounded-full border-red-500 bg-red-500"
                ]
                []
            , div
                [ Attr.class "w-3 h-3 border-2 rounded-full border-yellow-400 bg-yellow-400"
                ]
                []
            , div
                [ Attr.class "w-3 h-3 border-2 rounded-full border-green-400 bg-green-400"
                ]
                []
            ]
        ]


elmCodeBlock : String -> Html msg
elmCodeBlock elmCode =
    SyntaxHighlight.elm elmCode
        |> Result.map (SyntaxHighlight.toBlockHtml (Just 1))
        |> Result.withDefault
            (Html.pre [] [ Html.code [] [ Html.text elmCode ] ])


codeTabs : ( String, String ) -> Html msg
codeTabs fileName =
    ul
        [ Attr.class "flex text-sm text-blue-200"
        , Attr.style "transform" "translateY(0%) translateZ(0px);"
        ]
        [ codeTab 0 True fileName ]


codeTab : Int -> Bool -> ( String, String ) -> Html msg
codeTab index isCurrent ( fileName, fileContents ) =
    li
        [ Attr.class "flex-none"
        ]
        [ button
            [ Attr.type_ "button"
            , Attr.class
                ("border border-transparent py-2 px-4 font-medium text-blue-200 focus:outline-none hover:text-blue-100 "
                    ++ (if isCurrent then
                            "bg-blue-800"

                        else
                            "bg-transparent"
                       )
                )
            ]
            [ text fileName ]
        ]
