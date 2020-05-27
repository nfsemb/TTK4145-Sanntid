defmodule Button do
  @moduledoc """
    A module that defines a button struct.
  """
  defstruct floor: nil, type: nil

  def valid_button_types do
    [:up, :down, :cab]
  end
end
