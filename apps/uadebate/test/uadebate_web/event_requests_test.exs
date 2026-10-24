defmodule UadebateWeb.EventRequestsTest do
  # the rate-limit buckets and the app env are shared: not async
  use UadebateWeb.ConnCase, async: false

  import Swoosh.TestAssertions

  alias Uadebate.{EventRequests, Events, Roles}

  setup do
    CabWeb.RateLimit.reset()
    before = Application.get_env(:uadebate, :event_requests_email)
    Application.put_env(:uadebate, :event_requests_email, "requests@example.org")
    on_exit(fn -> Application.put_env(:uadebate, :event_requests_email, before) end)
  end

  defp editor do
    user = cab_user(%{name: "Iryna Editor"})
    {:ok, _} = Roles.grant(user.id)
    user
  end

  defp answers(extra \\ %{}) do
    Map.merge(
      %{
        "email" => "org@example.org",
        "name" => "Kyiv Open",
        "dates" => "2026-11-14 - 2026-11-16",
        "city" => "Kyiv",
        "format" => "BP",
        "details" => "Two days, eight rounds."
      },
      extra
    )
  end

  test "the calendar offers the request; the form asks the e-mail first", %{conn: conn} do
    calendar = conn |> get(~p"/calendar") |> html_response(200)
    assert calendar =~ ~s(href="/calendar/request")

    page = conn |> get(~p"/calendar/request") |> html_response(200)
    assert page =~ ~s(id="event-request-form")
    # cab's contact-field helpers run on the form (picker, spacing, checks)
    assert page =~ "/assets/js/contact-fields.js"
    [first | _] = Regex.scan(~r/name="answers\[([^\]]+)\]"/, page, capture: :all_but_first)
    assert first == ["email"]
    assert page =~ ~s(name="answers[name]")
  end

  test "a request is kept and e-mailed to the requester and the receiving address",
       %{conn: conn} do
    sent = conn |> post(~p"/calendar/request", %{answers: answers()}) |> html_response(200)
    assert sent =~ "org@example.org"

    assert [request] = EventRequests.pending()
    assert request.email == "org@example.org"

    assert_email_sent(fn email ->
      email.to == [{"", "org@example.org"}] and email.text_body =~ "Kyiv Open"
    end)

    assert_email_sent(fn email ->
      email.to == [{"", "requests@example.org"}] and email.text_body =~ "/manage/requests"
    end)
  end

  test "the e-mail is required and checked; nothing is kept", %{conn: conn} do
    page =
      conn
      |> post(~p"/calendar/request", %{answers: answers(%{"email" => "not an address"})})
      |> html_response(422)

    assert page =~ "name@example.com"
    assert EventRequests.pending() == []
    assert_no_email_sent()
  end

  test "five requests per address per hour", %{conn: conn} do
    for _ <- 1..5 do
      assert conn |> post(~p"/calendar/request", %{answers: answers()}) |> html_response(200)
    end

    limited = conn |> post(~p"/calendar/request", %{answers: answers()})
    assert html_response(limited, 429) =~ "Too many requests"
    assert [_ | _] = get_resp_header(limited, "retry-after")
    assert length(EventRequests.pending()) == 5
  end

  test "requests are for content managers only", %{conn: conn} do
    assert_error_sent 404, fn -> conn |> cab_sign_in(cab_user()) |> get(~p"/manage/requests") end

    page = conn |> cab_sign_in(editor()) |> get(~p"/manage/requests") |> html_response(200)
    assert page =~ ~s(href="/manage/requests")
    assert page =~ ~s(id="request-form")
    assert page =~ ~s(id="field-form")
  end

  test "accept: the event saved from the prefilled form accepts the request", %{conn: conn} do
    {:ok, request} = EventRequests.submit(answers(), "en")
    signed = cab_sign_in(conn, editor())

    form = signed |> get(~p"/manage/events/new?#{[request: request.id]}") |> html_response(200)
    assert form =~ ~s(name="request_id")
    assert form =~ "Kyiv Open"
    assert form =~ "2026-11-14"

    attrs = EventRequests.event_attrs(request)
    assert attrs["starts_on"] == "2026-11-14"
    assert attrs["ends_on"] == "2026-11-16"

    saved =
      signed
      |> post(~p"/manage/events", %{
        "request_id" => request.id,
        "event" => Map.put(attrs, "kind", "tournament")
      })

    assert redirected_to(saved) =~ "/manage/calendar"
    accepted = EventRequests.get!(request.id)
    assert accepted.status == "accepted"
    assert Events.get!(accepted.event_id).title == "Kyiv Open"

    assert_email_sent(fn email ->
      email.to == [{"", "org@example.org"}] and email.subject =~ "accepted"
    end)
  end

  test "decline: with the reason, e-mailed to the requester", %{conn: conn} do
    {:ok, request} = EventRequests.submit(answers(), "en")

    done =
      conn
      |> cab_sign_in(editor())
      |> post(~p"/manage/requests/#{request.id}/decline", %{"reason" => "Dates clash."})

    assert redirected_to(done) == "/manage/requests"
    declined = EventRequests.get!(request.id)
    assert declined.status == "declined"
    assert declined.reason == "Dates clash."

    assert_email_sent(fn email ->
      email.to == [{"", "org@example.org"}] and email.text_body =~ "Dates clash."
    end)
  end

  test "the form editor adds, moves and removes fields; the e-mail stays", %{conn: conn} do
    signed = cab_sign_in(conn, editor())

    added =
      signed
      |> post(~p"/manage/requests/form/fields", %{
        "label" => "Expected teams",
        "type" => "number",
        "required" => "no"
      })

    assert redirected_to(added) =~ "/manage/requests"
    form = EventRequests.form()
    assert %{"id" => id} = Enum.find(form, &(&1["label"] == "Expected teams"))

    signed |> post(~p"/manage/requests/form/fields/#{id}/move/up") |> redirected_to()
    signed |> post(~p"/manage/requests/form/fields/#{id}/remove") |> redirected_to()
    refute Enum.any?(EventRequests.form(), &(&1["id"] == id))

    # the e-mail cannot be removed
    signed |> post(~p"/manage/requests/form/fields/email/remove") |> redirected_to()
    assert hd(EventRequests.form())["id"] == "email"
  end
end
