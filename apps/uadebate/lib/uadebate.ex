defmodule Uadebate do
  @moduledoc """
  The public site, uadebate.com, at the top of the platform. It keeps
  its own news, calendar and content-manager roles, and reads the other
  services downward: clubs and accounts from cab. Dependencies point
  down (uadebate -> cab -> core).
  """

  @doc "Tournaments feed for the portal (calendar / front page)."
  defdelegate tournaments(params \\ []), to: Cab.EngineApi, as: :list_public_events
end
