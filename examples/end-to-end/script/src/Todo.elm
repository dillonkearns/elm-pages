module Todo exposing (run)

import BackendTask exposing (BackendTask)
import Db
import FatalError exposing (FatalError)
import Pages.Db
import Pages.Script as Script exposing (Script)


run : Script
run =
    Script.withoutCliOptions loop


loop : BackendTask FatalError ()
loop =
    Pages.Db.get Pages.Db.default
        |> BackendTask.andThen
            (\db ->
                printTodos db
                    |> BackendTask.andThen
                        (\_ ->
                            Script.log "\n(a)dd  (t)oggle  (d)elete  (q)uit"
                                |> BackendTask.andThen (\_ -> Script.readKey)
                        )
                    |> BackendTask.andThen (\key -> handleInput key db.todos)
            )


printTodos : Db.Db -> BackendTask FatalError ()
printTodos db =
    let
        todoLines =
            if List.isEmpty db.todos then
                "  (no items)"

            else
                db.todos
                    |> List.indexedMap
                        (\i t ->
                            let
                                check =
                                    if t.completed then
                                        "[x]"

                                    else
                                        "[ ]"
                            in
                            "  " ++ String.fromInt (i + 1) ++ ". " ++ check ++ " " ++ t.title
                        )
                    |> String.join "\n"
    in
    Script.log ("\n--- To-Do List ---\n" ++ todoLines)


handleInput : String -> List Db.Todo -> BackendTask FatalError ()
handleInput key todos =
    let
        idAtDisplayNum n =
            todos |> List.drop (n - 1) |> List.head |> Maybe.map .id
    in
    case key of
        "a" ->
            Script.question "Title: "
                |> BackendTask.andThen
                    (\title ->
                        Pages.Db.update Pages.Db.default
                            (\db ->
                                { db
                                    | todos =
                                        db.todos
                                            ++ [ { id = db.nextId
                                                 , title = title
                                                 , completed = False
                                                 }
                                               ]
                                    , nextId = db.nextId + 1
                                }
                            )
                    )
                |> BackendTask.andThen (\_ -> loop)

        "t" ->
            Script.log "Toggle item #: "
                |> BackendTask.andThen (\_ -> Script.readKey)
                |> BackendTask.andThen
                    (\numKey ->
                        case String.toInt numKey |> Maybe.andThen idAtDisplayNum of
                            Just id ->
                                Pages.Db.update Pages.Db.default
                                    (\db ->
                                        { db
                                            | todos =
                                                List.map
                                                    (\t ->
                                                        if t.id == id then
                                                            { t | completed = not t.completed }

                                                        else
                                                            t
                                                    )
                                                    db.todos
                                        }
                                    )
                                    |> BackendTask.andThen (\_ -> loop)

                            Nothing ->
                                Script.log "Invalid number."
                                    |> BackendTask.andThen (\_ -> loop)
                    )

        "d" ->
            Script.log "Delete item #: "
                |> BackendTask.andThen (\_ -> Script.readKey)
                |> BackendTask.andThen
                    (\numKey ->
                        case String.toInt numKey |> Maybe.andThen idAtDisplayNum of
                            Just id ->
                                Pages.Db.update Pages.Db.default
                                    (\db ->
                                        { db
                                            | todos =
                                                List.filter (\t -> t.id /= id) db.todos
                                        }
                                    )
                                    |> BackendTask.andThen (\_ -> loop)

                            Nothing ->
                                Script.log "Invalid number."
                                    |> BackendTask.andThen (\_ -> loop)
                    )

        "q" ->
            Script.log "Bye!"

        _ ->
            Script.log ("Unknown command: " ++ key)
                |> BackendTask.andThen (\_ -> loop)
