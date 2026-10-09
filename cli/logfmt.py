import os
import sys
import click
import logging


class ColorFormatter(logging.Formatter):

    def __init__(self, fmt, color=True):
        super().__init__(fmt)
        self._color = color

        self._colors = {
            logging.CRITICAL: "red",
            logging.ERROR:    "red",
            logging.WARNING:  "yellow",
            logging.INFO:     "green",
            logging.DEBUG:    "magenta",
        }

        self._marks = {
            logging.CRITICAL: "!",
            logging.ERROR:    "E",
            logging.WARNING:  "W",
            logging.INFO:     "*",
            logging.DEBUG:    "D",
        }

    def format(self, rec):
        marks, colors = self._marks, self._colors
        if not self._color:
            return f"[{marks[rec.levelno]}] {super().format(rec)}"
        return "".join([
            click.style("[",                fg="blue",              bold=True),
            click.style(marks[rec.levelno], fg=colors[rec.levelno], bold=True),
            click.style("]",                fg="blue",              bold=True),
            " ",
            super().format(rec),
        ])


class ExitOnExceptionHandler(logging.StreamHandler):

    def emit(self, record):
        super().emit(record)
        if record.levelno == logging.CRITICAL:
            raise SystemExit(127)


def setup_logging(level=logging.INFO):
    logging.basicConfig(handlers=[ExitOnExceptionHandler()])
    log = logging.getLogger()
    log.setLevel(level)
    handler = log.handlers[0]
    # Respect https://no-color.org and avoid escape codes when output is piped
    # (for example when the server runs inside the macOS app).
    color = not os.environ.get("NO_COLOR") and sys.stderr.isatty()
    handler.setFormatter(ColorFormatter("%(message)s", color=color))
    return log
