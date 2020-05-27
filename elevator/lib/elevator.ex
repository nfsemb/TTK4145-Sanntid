defmodule Elevator do
  @moduledoc """
  Main module, responsible for starting the supervision tree containing the different processes of a node.
  """
  @standardElevatorSimPort Application.compile_env(:elevator, :standardElevatorSimPort)
  @standardElevatorSimIP Application.compile_env(:elevator, :standardElevatorSimIP)
  use Application
  @doc "Starts the elevator application by starting the top level `Supervisor`."
  def start(:normal \\ :normal, [port] \\ [@standardElevatorSimPort]) do
    children = [
      {Network, [port]},
      BackupHandler,
      OrderWatchdog,
      {Driver, [@standardElevatorSimIP, port]},
      Output,
      OrderDistributor,
      OrderHandler,
      Fsm
    ]

    Supervisor.start_link(children, strategy: :one_for_one)
  end
end
