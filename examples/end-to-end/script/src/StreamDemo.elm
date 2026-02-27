module StreamDemo exposing (run)

import BackendTask exposing (BackendTask)
import FilePath exposing (FilePath)
import BackendTask.Stream as Stream exposing (Stream)
import FatalError exposing (FatalError)
import Json.Decode as Decode
import Pages.Script as Script exposing (Script)


run : Script
run =
    Script.withoutCliOptions
        --Stream.fileRead (FilePath.fromString "elm.json")
        --Stream.command "ls" [ "-l" ]
        --    |> Stream.pipe Stream.stdout
        --    |> Stream.run
        --elmFormatString : Stream { read : (), write : Never }
        --elmFormatString string =
        --    string
        --        |> Stream.fromString
        --        |> Stream.pipe
        --Stream.fileRead (FilePath.fromString "script/src/StreamDemo.elm")
        --Stream.stdin
        --    |> Stream.pipe (Stream.command "elm-format" [ "--stdin" ])
        --    --|> Stream.pipe (Stream.fileWrite (FilePath.fromString "my-formatted-example.elm"))
        --    |> Stream.pipe Stream.stdout
        --    |> Stream.run
        --unzip
        (zip
            |> BackendTask.andThen
                (\_ ->
                    readType
                        |> BackendTask.andThen
                            (\type_ ->
                                Script.log ("Found type: " ++ type_)
                            )
                 --Stream.fileRead zipFile
                 --    |> Stream.pipe Stream.unzip
                 --    |> Stream.pipe (Stream.command "jq" [ ".type" ])
                 --    |> Stream.pipe Stream.stdout
                 --    |> Stream.run
                )
        )



--unzip


readType : BackendTask FatalError String
readType =
    Stream.fileRead zipFile
        |> Stream.pipe Stream.unzip
        |> Stream.readJson (Decode.field "type" Decode.string)
        |> BackendTask.allowFatal
        |> BackendTask.map .body


zip =
    --Stream.command "elm-review" [ "--report=json" ]
    --|> Stream.pipe Stream.stdout
    --Stream.command "ls" [ "-l" ]
    Stream.fileRead (FilePath.fromString "elm.json")
        |> Stream.pipe Stream.gzip
        --|> Stream.pipe Stream.stdout
        |> Stream.pipe (Stream.fileWrite zipFile)
        |> Stream.run


unzip : BackendTask FatalError ()
unzip =
    Stream.fileRead zipFile
        |> Stream.pipe Stream.unzip
        |> Stream.pipe Stream.stdout
        |> Stream.run


zipFile : FilePath
zipFile =
    FilePath.fromString "elm-review-report.gz.json"


example1 : BackendTask FatalError ()
example1 =
    formatFile
        (Stream.fromString
            """module            Foo

a = 1
b =            2
        """
        )
        (Stream.fileWrite (FilePath.fromString "my-formatted-example.elm"))


example2 : BackendTask FatalError ()
example2 =
    formatFile
        (Stream.fileRead (FilePath.fromString "script/src/StreamDemo.elm"))
        Stream.stdout


formatFile source destination =
    source
        |> Stream.pipe (Stream.command "elm-format" [ "--stdin" ])
        |> Stream.pipe destination
        |> Stream.run



--Kind of a cool thing with the phantom record type there, you can annotate things in a more limited way if you choose to if you know that a given command doesn't accept `stdin` (and therefore can't be piped to), or doesn't give meaningful output (and therefore you don't want things to pipe from it).
--command : String -> List String -> Stream { read : read, write : write }
--elmFormatString : Stream { read : (), write : Never }
--elmFormatString string =
--    string
--        |> Stream.fromString
--        |> Stream.pipe (Stream.command "elm-format" "--stdin")
--
--
--chmodX : String -> Stream { read : Never, write : Never }
