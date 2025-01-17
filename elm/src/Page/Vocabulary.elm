module Page.Vocabulary exposing (Model, Msg, init, subscriptions, update, view)

import Api exposing (audioUrl, userReplace)
import Favorites exposing (Favored)
import Html exposing (..)
import Html.Attributes exposing (..)
import Html.Events exposing (onClick)
import Html.Parser
import Html.Parser.Util
import Http
import HttpBuilder exposing (RequestBuilder, withBody, withExpect)
import Task
import Route exposing (Route)
import Session exposing (Session)
import Svg exposing (svg, use)
import Svg.Attributes as SvgAttributes
import Viewer exposing (Viewer)
import Vocabulary exposing (Explan(..), Sense, Vocabulary(..), Word, decoder)
import Vocabulary.Id as Id exposing (Id)
import Vocabulary.Slug as Slug exposing (Slug)
import Loading
import Recent


type alias Model =
    { session : Session
    , errors : List String
    , selectedEntry : Maybe Id
    , vocabulary : Status Vocabulary
    }


type Status a
    = Loaded a
    | Loading
    | LoadingSlowly
    | Failed


init : Session -> Slug -> Maybe Id -> ( Model, Cmd Msg )
init session slug maybeId =
    ( { session = session
      , errors = []
      , selectedEntry = maybeId
      , vocabulary = Loading
      }
    , Cmd.batch
        [ fetch slug
        , Task.perform (\_ -> PassedSlowLoadThreshold) Loading.slowThreshold
        ]
    )


view : Model -> { title : String, content : Html Msg }
view model =
    let
        title =
            case model.vocabulary of
                Loaded v ->
                    "loaded"

                Loading ->
                    "loading"

                LoadingSlowly ->
                    "loading"

                Failed ->
                    "failed"

        ( enries, related ) =
            sideNav model.vocabulary model.selectedEntry
        vocabulary = 
            case model.vocabulary of
                Loaded voc ->
                    case voc of
                        Vocabulary _ ->
                            vocabularyView model.selectedEntry voc (Session.viewer model.session)
                        Suggestion sug ->
                            suggestionView sug                            
                    
                Loading ->
                    [ div [class "vocabulary__loading"] 
                        [ p [class "vocabulary__loading-text"] [ text "" ] ]
                    ]

                LoadingSlowly ->
                    [ div [class "vocabulary__loading"] 
                        [ p [class "vocabulary__loading-text"] [ text "loadingSlowly" ] ]
                    ]
                Failed ->
                    [ text "faild" ]
    in
    { title = title
    , content =
        div [ class "content" ]
            [ div [ class "side-bar" ]
                [ div [ class "side-nav" ]
                    [ enries
                    , related
                    ]
                ]
            , div [ class "vocabulary" ] vocabulary
            ]
    }


relatedLink : Route -> Html msg -> Html msg
relatedLink route linkContent =
    li [ class "entries__item" ] [ a [ Route.href route, class "entries__link" ] [ linkContent ] ]


entryBtn : Attribute msg -> msg -> Html msg -> Html msg
entryBtn attr msg btnContent =
    li [ class "entries__item" ] [ button [ attr, onClick msg ] [ btnContent ] ]


sideNav : Status Vocabulary -> Maybe Id -> ( Html Msg, Html msg )
sideNav vocabulary selectedEntry =
    case vocabulary of
        Loaded voc ->
            let
                toEntryBtn word =
                    let
                        headword =
                            Vocabulary.headword word

                        functionalLabel =
                            Maybe.withDefault "" << Maybe.map (\fl -> "  (" ++ fl ++ ")") <| word.functionalLabel

                        isSelected =
                            Maybe.withDefault False
                            <| Maybe.map (Id.isEq word.id) selectedEntry
                    in
                    entryBtn (classList [ ( "entries__btn", True ), ( "entries__btn--selected", isSelected ) ]) (ClickedEntry word.id) (text (headword ++ functionalLabel))

                toRelatedLink word =
                    let
                        headword =
                            Vocabulary.headword word
                        functionalLabel =
                            Maybe.withDefault "" << Maybe.map (\fl -> "  (" ++ fl ++ ")") <| word.functionalLabel
                    in
                    relatedLink (Route.Vocabulary word.slug Nothing) (text <| headword ++ functionalLabel)
            in
            ( div [ class "entries entries-thisword mb-md" ]
                [ h3 [ class "entries__title heading-3" ] [ text "entries" ]
                , ul [ class "entries__list" ] <|
                    List.map toEntryBtn (Vocabulary.entries voc)
                ]
            , div [ class "entries entries-otherword" ]
                [ h3 [ class "entries__title heading-3" ] [ text "Relate word" ]
                , ul [ class "entries__list" ] <|
                    List.map toRelatedLink (Vocabulary.relatedWord voc)
                ]
            )

        Loading ->
            ( div [class "entries entries__loading"] []
            , text "" 
            )

        LoadingSlowly ->
            ( div [class "entries entries__loading"] []
            , text "" 
            )

        Failed ->
            ( text "faild", text "" )

suggestionView :  List { a | headword : String, slug : Slug } -> List (Html msg)
suggestionView sug =
    let
        toLink suggest = 
            li [class "vocabulary__suggestion-item"] 
                [ a [Route.href (Route.Vocabulary suggest.slug Nothing), class "vocabulary__link"] [text suggest.headword] ]
            
    in
        [section [class "vocabulary__suggestion"]
            [ h4 [class "vocabulary__not-found heading-3"] [text "Not Found"]
            , p [class "vocabulary__tip"] [text "The word you have entered is not in the dictionary. try your search again"]
            , ol [class "vocabulary__suggestion-list"] <|
                List.map toLink sug
            ]
        ]

vocabularyView : Maybe Id -> Vocabulary -> Viewer -> List (Html Msg)
vocabularyView selectedEntry voc viewer =
    let
        words =
            case selectedEntry of
                Just id ->
                    List.filter (\w -> Id.isEq w.id id) (Vocabulary.entries voc)

                Nothing ->
                    []

        wordView word =
            div [ class "vocabulary__container" ] <|
                List.concat
                    [ [ headerView word ]
                    , [ shortDefineView word.shortDefine ]
                    , fullDefineView word.define
                    , [ crossReffencesView word.crossReffences ]
                    ]

        headerView word =
            header [ class "vocabulary__header  mb-sm" ]
                [ h2 [ class "vocabulary__headword heading-1" ] [ text word.headword ]
                , case word.functionalLabel of
                    Just label ->
                        span [ class "vocabulary__functional-label" ] [ text label ]

                    Nothing ->
                        text ""
                , div [ class "vocabulary__pronunciation" ]
                    [ case word.ipa of
                        Just ipa ->
                            span [ class "vocabulary__ipa" ] [ text ipa ]

                        Nothing ->
                            text ""
                    , case word.audio of
                        Just filename ->
                            button [ class "vocabulary__sound", onClick ClickedAudio ]
                                [ svg [ SvgAttributes.class "vocabulary__sound-icon" ] [ use [ SvgAttributes.xlinkHref "/img/sprite.svg#icon-audio" ] [] ]
                                , audio [ class "vocabulary__sound-audio", id "audio", src (audioUrl filename) ] []
                                ]

                        Nothing ->
                            text ""
                    ]
                , favoriteButton viewer word
                ]

        shortDefineView shortDefine =
            div [ class "vocabulary__brief" ]
                [ ul [ class "vocabulary__brief-list" ] <|
                    List.map
                        (\str -> li [ class "vocabulary__brief-item" ] [ text str ])
                        shortDefine
                ]

        fullDefineView define =
            case define of
                Just listOfDefine ->
                    List.map
                        (\listOfSenses ->
                            div [ class "vocabulary__definition" ] <|
                                List.map senseView listOfSenses
                        )
                        listOfDefine

                Nothing ->
                    [ text "" ]

        crossReffencesView crossRef =
            case crossRef of
                Just cr ->
                    div [ class "vocabulary__crossRef" ]
                        [ p [] (textHtml cr) ]

                Nothing ->
                    text ""
    in
    List.map wordView words



senseView : Sense -> Html msg
senseView sense =
    let
        explanView explan =
            case explan of
                Meaning mean ->
                    if String.contains "see also" mean then
                        p [ class "vocabulary__seealso" ] (textHtml mean)

                    else
                        figcaption [ class "vocabulary__senses-text" ] <|
                            [ if (String.isEmpty >> not) sense.grammatical then
                                span [ class "vocabulary__label" ] [ text sense.grammatical ]

                              else
                                text ""
                            ]
                                ++ textHtml mean

                ExampleSentence sentences ->
                    sentencesView sentences

                UsageNote note ->
                    div [ class "vocabulary__usage" ]
                        [ p [ class "vocabulary__usage-text" ] (textHtml note.text)
                        , sentencesView note.example
                        ]

                GrammaticalLabel lable ->
                    p [ class "vocabulary__label" ] [ text lable ]

                _ ->
                    text ""
    in
    case sense.explan of
        Nothing ->
            span [ class "vocabulary__grammatical" ] [ text sense.grammatical ]

        Just explans ->
            figure [ class "vocabulary__senses" ] <|
                List.map explanView explans



-- ]


sentencesView : List String -> Html msg
sentencesView sentences =
    ul [ class "vocabulary__list-example" ] <|
        List.map (\s -> li [ class "vocabulary__example" ] (textHtml s)) sentences


favoriteButton : Viewer -> Word -> Html Msg
favoriteButton viewer word =
    let
        favorited =
            Favorites.isFavorited word.headword <|
                Viewer.favorites viewer
    in
    if favorited then
        button [ class "vocabulary__save", onClick (ClickedUnfavorite viewer word) ]
            [ svg [ SvgAttributes.class "vocabulary__save-icon" ] [ use [ SvgAttributes.xlinkHref "/img/sprite.svg#icon-star-full" ] [] ] ]

    else
        button [ class "vocabulary__save", onClick (ClickedFavorite viewer word) ]
            [ svg [ SvgAttributes.class "vocabulary__save-icon" ] [ use [ SvgAttributes.xlinkHref "/img/sprite.svg#icon-star" ] [] ] ]


textHtml : String -> List (Html.Html msg)
textHtml sentence =
    case Html.Parser.run (tokenParser sentence) of
        Ok nodes ->
            Html.Parser.Util.toVirtualDom nodes

        -- [text sentence]
        Err _ ->
            []


type Msg
    = CompetedVocabularyLoad (Result Http.Error Vocabulary)
    | ClickedEntry Id
    | ClickedAudio
    | ClickedFavorite Viewer Word
    | ClickedUnfavorite Viewer Word
    | GotSession Session
    | PassedSlowLoadThreshold


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of

        ClickedEntry id ->
            ( { model | selectedEntry = Just id }, Cmd.none )

        ClickedAudio ->
            ( model, Api.soundCmdToJs "play" )

        ClickedFavorite viewer word ->
            ( model, Viewer.favorite viewer (Vocabulary.toFavored word) )

        ClickedUnfavorite viewer word ->
            ( model, Viewer.unfavorite viewer (Vocabulary.toFavored word) )
        CompetedVocabularyLoad (Ok vocabulary) ->
                            let
                                e =
                                    Debug.log "voc" vocabulary
                            in
            ( { model 
              | vocabulary = Loaded vocabulary
              , selectedEntry = 
                case model.selectedEntry of
                    Nothing ->
                        (List.head << List.map (\w -> w.id)) (Vocabulary.entries vocabulary) 
                    id ->
                        id
              }
            , case vocabulary of
                Vocabulary info ->
                    let
                        viewer = Session.viewer model.session
                    in
                    case List.head info.entries of
                        Just word ->
                            Vocabulary.toLastWord word
                                |> Recent.add (Viewer.recent viewer)
                                |> Viewer.updateRecent viewer
                                |> Viewer.store
                        Nothing ->
                            Cmd.none                            
                Suggestion _ ->
                    Cmd.none
                    
             )

        CompetedVocabularyLoad (Err errors) ->
            let
                e =
                    Debug.log "error" errors
            in
            ( { model | errors = Api.decodeErrors errors, vocabulary = Failed }, Cmd.none )
        PassedSlowLoadThreshold -> 
            let
                voc = 
                    case model.vocabulary of
                        Loading ->
                            LoadingSlowly
                        other ->
                            other
            in
            ( {model | vocabulary = voc}, Cmd.none)
            
        GotSession session ->
            ( { model | session = session }, Cmd.none )



-- Http


fetch : Slug -> Cmd Msg
fetch slug =
    let
        expect =
            Http.expectJson CompetedVocabularyLoad (decoder slug)
    in
    Api.url [ Slug.toString slug ]
        |> HttpBuilder.get
        |> HttpBuilder.withExpect expect
        |> HttpBuilder.request


subscriptions : Model -> Sub Msg
subscriptions model =
    Session.changes GotSession (Session.navKey model.session)



-- tokenparser


tokenParser : String -> String
tokenParser sentence =
    let
        replacePattern match =
            case match.match of
                "{bc}" ->
                    ""

                "{it}" ->
                    "<i>"

                "{/it}" ->
                    "</i>"

                "{phrase}" ->
                    "<em>"

                "{/phrase}" ->
                    "</em>"

                "{dx}" ->
                    ""

                "{/dx}" ->
                    ""

                "{ldquo}" ->
                    "“"

                "{rdquo}" ->
                    "”"

                _ ->
                    if String.contains "dxt" match.match then
                        (Maybe.withDefault "" << List.head) <|
                            List.map
                                (Maybe.map (\s -> "<span style=\"font-weight: bold\">" ++ s ++ "</span>") >> Maybe.withDefault "")
                                match.submatches

                    else if String.contains "{sx" match.match then
                        List.foldl (++) "" <|
                            List.map
                                (Maybe.map (\s -> "<a style='font-weight: bold; color: #bbb' href='" ++ s ++ "'>  " ++ s ++ "</a>") >> Maybe.withDefault "")
                                match.submatches

                    else
                        "+++++"

        replacer =
            userReplace "\\{bc\\}|\\{it\\}|\\{\\/it\\}|\\{\\/phrase\\}|\\{phrase\\}|\\{dx\\}|\\{\\/dx\\}|\\{dxt\\|([\\w\\s]*)[\\:\\d]*\\|\\|[\\w\\s\\(\\)]*?\\}|\\{ldquo\\}|\\{rdquo\\}|\\{sx\\|([\\w\\s]*)[\\:\\d]*\\|\\|\\}" replacePattern
    in
    replacer sentence

