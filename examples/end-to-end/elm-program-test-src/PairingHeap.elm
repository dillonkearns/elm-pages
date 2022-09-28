module PairingHeap exposing
    ( PairingHeap, empty
    , insert, merge, findMin, deleteMin
    , fromList, toSortedList
    )

{-| This is a simple pairing heap implementation written in Elm usable as a priority queue. This code is
based heavily on the pseudocode available at [the Wikipedia page](https://en.wikipedia.org/wiki/Pairing_heap).


# Type and Constructor

@docs PairingHeap, empty


# Operations

@docs insert, merge, findMin, deleteMin


# Convenience functions

@docs fromList, toSortedList

-}


{-| A `PairingHeap` has comparable keys and values of an arbitrary type.
-}
type PairingHeap comparable a
    = Empty
    | Heap comparable a (List (PairingHeap comparable a))


{-| Create an empty PairingHeap.
-}
empty : PairingHeap comparable a
empty =
    Empty


{-| Find the minimum value in a heap returning Nothing if the heap is empty.
Complexity: O(1)

    findMin (fromList [ ( 10, () ), ( 3, () ), ( 8, () ) ]) == Just 3

-}
findMin : PairingHeap comparable a -> Maybe ( comparable, a )
findMin x =
    case x of
        Empty ->
            Nothing

        Heap k v _ ->
            Just ( k, v )


{-| Merges two `PairingHeap`s together into one new heap containing all of the key-value pairs from both inputs.
Complexity: O(1)
-}
merge : PairingHeap comparable a -> PairingHeap comparable a -> PairingHeap comparable a
merge heap1 heap2 =
    case ( heap1, heap2 ) of
        ( Empty, _ ) ->
            heap2

        ( _, Empty ) ->
            heap1

        ( Heap k1 v1 hs1, Heap k2 v2 hs2 ) ->
            if k1 < k2 then
                Heap k1 v1 (heap2 :: hs1)

            else
                Heap k2 v2 (heap1 :: hs2)


{-| Inserts a new element into a `PairingHeap`.
Complexity: O(1)
-}
insert : comparable -> a -> PairingHeap comparable a -> PairingHeap comparable a
insert k v heap =
    merge (Heap k v []) heap


{-| Removes the minimum element from a `PairingHeap` returning a new heap without that element.
This will return an empty heap if given an empty heap as input.
Complexity: O(log n)
-}
deleteMin : PairingHeap comparable a -> PairingHeap comparable a
deleteMin heap =
    case heap of
        Empty ->
            Empty

        Heap k v heaps ->
            mergePairs heaps


{-| This is an internal function used by deleteMin.
-}
mergePairs : List (PairingHeap comparable a) -> PairingHeap comparable a
mergePairs heaps =
    case heaps of
        [] ->
            Empty

        x :: [] ->
            x

        x :: (y :: xs) ->
            merge (merge x y) (mergePairs xs)



-- Extra convenience functions


{-| This function turns a list of key-value pairs into a `PairingHeap`.
Complexity: O(n)
-}
fromList : List ( comparable, a ) -> PairingHeap comparable a
fromList =
    List.foldl (\( k, v ) -> insert k v) empty


{-| This function turns a `PairingHeap` into a sorted list of key-value pairs.
Complexity: O(n log n)
-}
toSortedList : PairingHeap comparable a -> List ( comparable, a )
toSortedList heap =
    case heap of
        Empty ->
            []

        Heap k v _ ->
            ( k, v ) :: toSortedList (deleteMin heap)
