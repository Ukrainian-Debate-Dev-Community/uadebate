defmodule UadebateWeb.Emails do
  @moduledoc """
  uadebate.com's e-mails about event requests, plain text from cab's
  sender address (config :cab, :mail_from), each in the language of the
  page the request was sent from: the requester's copy, the notice to
  the address that receives requests (config :uadebate,
  :event_requests_email; none set, no notice), and the decision.
  """
  use Gettext, backend: UadebateWeb.Gettext

  import Swoosh.Email

  require Logger

  alias Uadebate.EventRequests.Request

  @doc "The requester's copy of what they sent."
  def request_received(%Request{} = request) do
    in_language(request, fn ->
      deliver(
        request.email,
        gettext("Your event request"),
        gettext(
          "Thank you: we received your request for an event in the calendar. We will write to this address once it is decided.\n\nWhat you sent:\n\n%{answers}",
          answers: answers_text(request)
        )
      )
    end)
  end

  @doc "The notice to the address that receives requests, if one is set."
  def request_notice(%Request{} = request) do
    case Application.get_env(:uadebate, :event_requests_email) do
      address when is_binary(address) and address != "" ->
        in_language(request, fn ->
          deliver(
            address,
            gettext("New event request"),
            gettext(
              "A new request for an event in the calendar.\n\n%{answers}\n\nAccept or decline it: %{url}",
              answers: answers_text(request),
              url: UadebateWeb.Endpoint.url() <> "/manage/requests"
            )
          )
        end)

      _none ->
        Logger.info("event request #{request.id}: no EVENT_REQUESTS_EMAIL, no notice sent")
        :ok
    end
  end

  @doc "The request was accepted: the event is in the calendar."
  def request_accepted(%Request{} = request, title) do
    in_language(request, fn ->
      deliver(
        request.email,
        gettext("Your event request was accepted"),
        gettext("Your request was accepted: %{title} is in the calendar.\n\n%{url}",
          title: title,
          url: UadebateWeb.Endpoint.url() <> "/calendar"
        )
      )
    end)
  end

  @doc "The request was declined, with the reason when one was given."
  def request_declined(%Request{} = request) do
    in_language(request, fn ->
      body =
        if request.reason,
          do: gettext("Your request for an event was declined.\n\nReason: %{reason}", reason: request.reason),
          else: gettext("Your request for an event was declined.")

      deliver(request.email, gettext("Your event request was declined"), body)
    end)
  end

  defp answers_text(%Request{answers: answers}) do
    Enum.map_join(answers, "\n", fn answer ->
      "#{CabWeb.FormComponents.field_label(answer)}: #{CabWeb.FormComponents.answer_text(answer)}"
    end)
  end

  defp in_language(%Request{locale: locale}, fun) do
    Gettext.with_locale(UadebateWeb.Gettext, locale, fn ->
      Gettext.with_locale(CabWeb.Gettext, locale, fun)
    end)
  end

  defp deliver(address, subject, body) do
    new()
    |> to(address)
    |> from(Application.fetch_env!(:cab, :mail_from))
    |> subject(subject)
    |> text_body(body)
    |> Core.Mailer.deliver()
    |> case do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end
end
