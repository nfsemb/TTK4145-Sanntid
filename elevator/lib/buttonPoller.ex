defmodule ButtonPoller do
  @moduledoc """
    A module that observes if a button is pressed or not, passing a message on rising flank.
  """
  use Task, restart: :permanent
  require Driver

  @pollingRate Application.compile_env(:elevator, :pollingRate)

  # Public functions
  # --------------------------------------------

  @doc "Starts a task monitoring a given button."
  def start_link(button) do
    Task.start_link(__MODULE__, :poller, [button, :off])
  end

  # Recursive function for periodically polling a button.
  def poller(button, prev) do
    current = Driver.get_order_button_state(button.floor, button.type)

    case {prev, current} do
      # Checks a rising-flank event is occuring this time
      {:off, :on} ->
        # Sends update {floor, type} to the Order Distributor that a new order is received
        OrderDistributor.buttonPressed({button.floor, button.type})

      _ ->
        nil
    end

    :timer.sleep(@pollingRate)
    poller(button, current)
  end
end
