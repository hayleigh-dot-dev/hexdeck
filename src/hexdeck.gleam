// IMPORTS ---------------------------------------------------------------------

import gleam/bool
import gleam/dict.{type Dict}
import gleam/dynamic.{type DecodeError, type Dynamic, dynamic}
import gleam/int
import gleam/list
import gleam/option.{type Option}
import gleam/pair
import gleam/result
import gleam/string
import gleam/uri
import lustre
import lustre/attribute.{type Attribute}
import lustre/effect.{type Effect}
import lustre/element.{type Element}
import lustre/element/html
import lustre/event
import modem

// MAIN ------------------------------------------------------------------------

pub fn main() {
  let app = lustre.application(init, update, view)

  let assert Ok(_) = lustre.start(app, "#app", Nil)

  Nil
}

// MODEL -----------------------------------------------------------------------

type Model {
  Model(
    next: Int,
    expanded: Option(Int),
    order: List(Int),
    frames: Dict(Int, String),
  )
}

fn init(_) -> #(Model, Effect(Msg)) {
  let assert Ok(initial_uri) = modem.initial_uri()
  let #(order, frames) =
    option.to_result(initial_uri.query, Nil)
    |> result.then(uri.parse_query)
    |> result.map(fn(query) {
      use #(order, frames), #(key, value) <- list.fold_right(query, #(
        [],
        dict.new(),
      ))

      case int.parse(key) {
        Ok(key) -> {
          let order = [key, ..order]
          let frames = dict.insert(frames, key, value)

          #(order, frames)
        }

        Error(_) -> #(order, frames)
      }
    })
    |> result.unwrap(#([], dict.new()))
  let next = list.fold(order, 0, int.max) + 1

  let model = Model(next:, expanded: option.None, order:, frames:)
  let effect = update_query(order, frames)

  #(model, effect)
}

// UPDATE ----------------------------------------------------------------------

type Msg {
  UserAddedFrame(src: String)
  UserClickedExpand(id: Int)
  UserRemovedFrame(id: Int)
  UserUpdatedSrc(id: Int, src: String)
}

fn update(model: Model, msg: Msg) -> #(Model, Effect(Msg)) {
  case msg {
    UserAddedFrame(src) -> {
      let next = model.next + 1
      let order = [next, ..model.order]
      let frames = dict.insert(model.frames, next, src)

      let model = Model(..model, next:, order:, frames:)
      let effect = update_query(order, frames)

      #(model, effect)
    }

    UserClickedExpand(id) -> #(
      Model(
        ..model,
        expanded: case option.Some(id) == model.expanded {
          True -> option.None
          False -> option.Some(id)
        },
      ),
      effect.none(),
    )

    UserRemovedFrame(id) -> {
      let expanded = case option.Some(id) == model.expanded {
        True -> option.None
        False -> model.expanded
      }
      let order = list.filter(model.order, fn(x) { x != id })
      let frames = dict.delete(model.frames, id)

      let model = Model(..model, expanded:, order:, frames:)
      let effect = update_query(order, frames)

      #(model, effect)
    }

    UserUpdatedSrc(id, src) -> #(
      Model(..model, frames: dict.insert(model.frames, id, src)),
      effect.none(),
    )
  }
}

fn update_query(order: List(Int), frames: Dict(Int, String)) -> Effect(msg) {
  case order {
    [] -> modem.push("/", option.None, option.None)
    _ -> {
      let query =
        uri.query_to_string(
          list.filter_map(order, fn(key) {
            frames
            |> dict.get(key)
            |> result.try(fn(param) { Ok(string.lowercase(param)) })
            |> result.map(pair.new(int.to_string(key), _))
          }),
        )

      modem.push("/", option.Some(query), option.None)
    }
  }
}

// VIEW ------------------------------------------------------------------------

fn view(model: Model) -> Element(Msg) {
  html.div(
    [
      attribute.class("min-w-screen h-screen overflow-x-scrollspace-x-2 p-6"),
      attribute.class("snap-x whitespace-nowrap [&>*]:inline-block"),
    ],
    [
      element.keyed(element.fragment, {
        use children, key <- list.fold(model.order, [])
        let assert Ok(src) = dict.get(model.frames, key)

        let width =
          attribute.class(case option.Some(key) == model.expanded {
            True -> "w-[960px]"
            False -> "w-[480px]"
          })

        let child =
          view_embed_wrapper(key, src, [width], [
            html.iframe([
              attribute.class("w-full h-full"),
              attribute.src("https://hexdocs.pm/" <> src),
            ]),
          ])

        [#(int.to_string(key), child), ..children]
      }),
      view_embed_placeholder(),
    ],
  )
}

fn view_embed_wrapper(
  id: Int,
  src: String,
  attributes: List(Attribute(Msg)),
  children: List(Element(Msg)),
) -> Element(Msg) {
  html.article([attribute.class("h-full p-2 transition-width"), ..attributes], [
    html.div(
      [attribute.class("h-full w-full flex flex-col bg-white rounded-xl")],
      [
        html.header([attribute.class("flex items-center gap-2 p-2")], [
          html.button(
            [
              attribute.class("size-3 rounded-full bg-red-500 hover:bg-red-600"),
              event.on_click(UserRemovedFrame(id)),
            ],
            [],
          ),
          html.button(
            [
              attribute.class(
                "size-3 rounded-full bg-green-500 hover:bg-green-600",
              ),
              event.on_click(UserClickedExpand(id)),
            ],
            [],
          ),
          html.div(
            [
              attribute.class(
                "text-sm flex-1 flex px-2 py-1 rounded-lg bg-gray-100",
              ),
            ],
            [
              html.span([attribute.class("text-gray-400")], [
                html.text("https://hexdocs.pm/"),
              ]),
              html.input([
                attribute.class("bg-transparent flex-1"),
                attribute.attribute("autocapitalize", "off"),
                attribute.value(src),
              ]),
            ],
          ),
        ]),
        html.main([attribute.class("flex-1")], children),
      ],
    ),
  ])
}

fn view_embed_placeholder() -> Element(Msg) {
  html.article([attribute.class("h-full p-2 w-[396px]")], [
    html.div(
      [attribute.class("h-full w-full flex flex-col bg-white rounded-xl")],
      [
        html.header([attribute.class("flex items-center gap-2 p-2")], [
          html.div(
            [attribute.class("text-sm flex-1 px-2 py-1 rounded-lg bg-gray-100")],
            [
              html.span([attribute.class("text-gray-400")], [
                html.text("https://hexdocs.pm/"),
              ]),
              html.input([
                attribute.class("bg-transparent"),
                event.on("keydown", handle_placeholder_input_keydown),
              ]),
            ],
          ),
        ]),
        html.main([attribute.class("flex-1 flex items-center justify-center")], [
          html.text("Search for a new package..."),
        ]),
      ],
    ),
  ])
}

fn handle_placeholder_input_keydown(
  event: Dynamic,
) -> Result(Msg, List(DecodeError)) {
  use key <- result.try(dynamic.field("key", dynamic.string)(event))
  use <- bool.guard(key != "Enter", Error([]))
  use target <- result.try(dynamic.field("target", dynamic)(event))
  use value <- result.try(dynamic.field("value", dynamic.string)(target))
  use <- bool.guard(value == "", Error([]))

  blur(target)
  clear(target)

  Ok(UserAddedFrame(value))
}

@external(javascript, "./hexdeck.dom.mjs", "blur")
fn blur(_target: Dynamic) -> Nil {
  Nil
}

@external(javascript, "./hexdeck.dom.mjs", "clear")
fn clear(_target: Dynamic) -> Nil {
  Nil
}
