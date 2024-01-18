"""System load average detection module"""

import os
from contextlib import suppress
from typing import List

from archey.colors import Colors
from archey.entry import Entry


class LoadAverage(Entry):
    """System load average detection entry"""

    _ICON = "\U000f051f"  # md_timer_sand
    _PRETTY_NAME = "Load Average"

    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)

        with suppress(AttributeError):
            self.value = os.getloadavg()

    @property
    def pretty_value(self) -> List[tuple[str, str]]:
        if not self.value:
            # Fall back on the default behavior if load average values could not be detected.
            return super().pretty_value

        # DRY constant thresholds.
        decimal_places = self.options.get("decimal_places", 2)
        warning_threshold = self.options.get("warning_threshold", 1.0)
        danger_threshold = self.options.get("danger_threshold", 2.0)

        return [
            (
                self.name,
                " ".join(
                    [
                        str(Colors.get_level_color(load_avg, warning_threshold, danger_threshold))
                        + str(round(load_avg, decimal_places))
                        + str(Colors.CLEAR)
                        for load_avg in self.value
                    ]
                ),
            )
        ]
