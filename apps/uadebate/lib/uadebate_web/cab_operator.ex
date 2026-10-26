defmodule UadebateWeb.CabOperator do
  @moduledoc """
  Who runs cab for uadebate.com: the texts, links and addresses cab shows
  in its footer, on its sign-in and on its account page
  (`config :cab, :operator, UadebateWeb.CabOperator`).

  cab sets its own backend's locale per request and per LiveView, so the
  texts are translated with uadebate's words in that same language.
  """
  @behaviour CabWeb.Operator

  use Gettext, backend: UadebateWeb.Gettext

  @impl true
  def info do
    Gettext.with_locale(UadebateWeb.Gettext, Gettext.get_locale(CabWeb.Gettext), fn ->
      %{
        about:
          gettext(
            "Clubs across Ukraine run weekly practice rounds — pick one and come debate. Free for every Ukrainian club."
          ),
        site_url: "https://uadebate.com",
        org_text:
          gettext("Run by the NGO Debate Federation of Ukraine (ВМГО «Федерація Дебатів України»)."),
        org_label: gettext("DFU"),
        org_url: "https://uadebate.com/about",
        contact_email: "ngo.dfu@uadebate.com",
        support_email: "support@uadebate.com",
        signin_foot: gettext("Debate Federation of Ukraine") <> " — uadebate.com"
      }
    end)
  end
end
