defmodule Mijnverbruik.TelegramFixtures do
  @moduledoc "Telegram fixtures for tests (public example data, not a real household)."

  # DSMR 4.2 example telegram from the `dsmr` library README.
  def raw_telegram do
    Enum.join([
      "/KFM5KAIFA-METER\r\n",
      "\r\n",
      "1-3:0.2.8(42)\r\n",
      "0-0:1.0.0(161113205757W)\r\n",
      "0-0:96.1.1(3960221976967177082151037881335713)\r\n",
      "1-0:1.8.1(001581.123*kWh)\r\n",
      "1-0:1.8.2(001435.706*kWh)\r\n",
      "1-0:2.8.1(000000.000*kWh)\r\n",
      "1-0:2.8.2(000000.000*kWh)\r\n",
      "0-0:96.14.0(0002)\r\n",
      "1-0:1.7.0(02.027*kW)\r\n",
      "1-0:2.7.0(00.000*kW)\r\n",
      "0-0:96.7.21(00015)\r\n",
      "0-0:96.7.9(00007)\r\n",
      "1-0:99.97.0(3)(0-0:96.7.19)(000104180320W)(0000237126*s)(000101000001W)",
      "(2147583646*s)(000102000003W)(2317482647*s)\r\n",
      "1-0:32.32.0(00000)\r\n",
      "1-0:52.32.0(00000)\r\n",
      "1-0:72.32.0(00000)\r\n",
      "1-0:32.36.0(00000)\r\n",
      "1-0:52.36.0(00000)\r\n",
      "1-0:72.36.0(00000)\r\n",
      "0-0:96.13.1()\r\n",
      "0-0:96.13.0()\r\n",
      "1-0:31.7.0(000*A)\r\n",
      "1-0:51.7.0(006*A)\r\n",
      "1-0:71.7.0(002*A)\r\n",
      "1-0:21.7.0(00.170*kW)\r\n",
      "1-0:22.7.0(00.000*kW)\r\n",
      "1-0:41.7.0(01.247*kW)\r\n",
      "1-0:42.7.0(00.000*kW)\r\n",
      "1-0:61.7.0(00.209*kW)\r\n",
      "1-0:62.7.0(00.000*kW)\r\n",
      "0-1:24.1.0(003)\r\n",
      "0-1:96.1.0(4819243993373755377509728609491464)\r\n",
      "0-1:24.2.1(161129200000W)(00981.443*m3)\r\n",
      "!6796\r\n"
    ])
  end

  @doc "A parsed telegram with the given local winter time and delivered T1 kWh."
  def telegram(naive, delivered_kwh, equipment_id \\ "E1") do
    %DSMR.Telegram{
      header: "TEST",
      checksum: "",
      measured_at: %DSMR.Timestamp{value: naive, dst: "W"},
      equipment_id: equipment_id,
      electricity_delivered_1: %DSMR.Measurement{value: delivered_kwh, unit: "kWh"},
      electricity_delivered_2: %DSMR.Measurement{value: 0.0, unit: "kWh"},
      electricity_returned_1: %DSMR.Measurement{value: 0.0, unit: "kWh"},
      electricity_returned_2: %DSMR.Measurement{value: 0.0, unit: "kWh"}
    }
  end
end
