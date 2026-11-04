defmodule Mijnverbruik.Repo.Migrations.CreateHourSummaries do
  use Ecto.Migration

  # The first and last register values of each UTC hour per meter, so usage
  # per hour no longer means scanning every minute. Triggers keep it in step
  # with `readings`, whoever writes them.
  @columns ~w(delivered_t1_wh delivered_t2_wh returned_wh gas_l)

  def up do
    create table(:hour_summaries, primary_key: false) do
      add :hour, :integer, null: false
      add :equipment_id, :string, null: false

      for column <- @columns do
        add String.to_atom(column <> "_start"), :integer
        add String.to_atom(column <> "_end"), :integer
      end
    end

    create unique_index(:hour_summaries, [:hour, :equipment_id])

    execute "INSERT INTO hour_summaries " <> aggregate("1 = 1")

    execute """
    CREATE TRIGGER readings_hour_insert AFTER INSERT ON readings BEGIN
      INSERT INTO hour_summaries VALUES (
        NEW.minute / 3600 * 3600, NEW.equipment_id,
        NEW.delivered_t1_wh, NEW.delivered_t1_wh,
        NEW.delivered_t2_wh, NEW.delivered_t2_wh,
        NEW.returned_t1_wh + NEW.returned_t2_wh, NEW.returned_t1_wh + NEW.returned_t2_wh,
        NEW.gas_l, NEW.gas_l
      )
      ON CONFLICT (hour, equipment_id) DO UPDATE SET #{merge_columns()};
    END
    """

    for {event, row} <- [{"DELETE", "OLD"}, {"UPDATE", "OLD"}, {"UPDATE", "NEW"}] do
      execute """
      CREATE TRIGGER readings_hour_#{String.downcase(event)}_#{String.downcase(row)}
      AFTER #{event} ON readings BEGIN
        #{recompute(row)}
      END
      """
    end
  end

  def down do
    for name <- ~w(insert delete_old update_old update_new) do
      execute "DROP TRIGGER readings_hour_#{name}"
    end

    drop table(:hour_summaries)
  end

  # Readings are only ever inserted by the app; deletes and updates rebuild
  # the affected hour from scratch.
  defp recompute(row) do
    hour = "#{row}.minute / 3600 * 3600"

    """
    DELETE FROM hour_summaries WHERE hour = #{hour} AND equipment_id = #{row}.equipment_id;
    INSERT INTO hour_summaries #{aggregate("minute >= #{hour} AND minute < #{hour} + 3600 AND equipment_id = #{row}.equipment_id")};
    """
  end

  defp aggregate(where) do
    """
    SELECT minute / 3600 * 3600, equipment_id,
           MIN(delivered_t1_wh), MAX(delivered_t1_wh),
           MIN(delivered_t2_wh), MAX(delivered_t2_wh),
           MIN(returned_t1_wh + returned_t2_wh), MAX(returned_t1_wh + returned_t2_wh),
           MIN(gas_l), MAX(gas_l)
    FROM readings WHERE #{where}
    GROUP BY minute / 3600 * 3600, equipment_id
    """
  end

  # Registers only grow, but an hour's minutes may arrive out of order. NULL
  # gas readings never replace a known value.
  defp merge_columns do
    @columns
    |> Enum.flat_map(fn c ->
      [
        "#{c}_start = MIN(COALESCE(#{c}_start, excluded.#{c}_start), COALESCE(excluded.#{c}_start, #{c}_start))",
        "#{c}_end = MAX(COALESCE(#{c}_end, excluded.#{c}_end), COALESCE(excluded.#{c}_end, #{c}_end))"
      ]
    end)
    |> Enum.join(", ")
  end
end
