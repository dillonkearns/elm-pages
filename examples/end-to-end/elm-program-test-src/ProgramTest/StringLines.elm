module ProgramTest.StringLines exposing (charAt, replaceAt)


charAt : Int -> Int -> String -> Maybe String
charAt row col input =
    String.lines input
        |> List.drop (row - 1)
        |> List.head
        |> Maybe.map
            (String.dropLeft (col - 1)
                >> String.left 1
            )


replaceAt : Int -> Int -> String -> String -> String
replaceAt row col replacement input =
    String.lines input
        |> List.indexedMap
            (\i line ->
                if i == (row - 1) then
                    String.left (col - 1) line ++ replacement ++ String.dropLeft col line

                else
                    line
            )
        |> String.join "\n"
