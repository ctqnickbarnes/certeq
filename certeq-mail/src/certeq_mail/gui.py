"""Certeq Console — Tkinter replacement for the VBA Certeq_Menu_KVS1 and
API_Login UserForms.

Thin front-end over the CLI: buttons call the same build_email()/api/outlook
functions, so all template and API logic stays in one place. Launch with
`uv run certeq-gui`.
"""

import queue
import threading
import time
import tkinter as tk
from tkinter import messagebox, ttk

import keyring

from . import api, outlook
from .cli import build_email

BUTTONS = [
    ("SOE Recovery (AU)", "soe-au"),
    ("SOE Recovery (NZ)", "soe-nz"),
    ("DMaaS Staging (AU)", "dmaas-au"),
    ("DMaaS Staging (NZ)", "dmaas-nz"),
    ("Maxtel Checks", "maxtel"),
    ("Completion", "completion"),
    ("Completion Issues", "issues"),
    ("Issues Update", "issues-update"),
]

PAD = {"padx": 6, "pady": 4}


class App:
    def __init__(self) -> None:
        self.root = tk.Tk()
        self.root.title("Certeq Console")
        self.root.resizable(False, False)
        self.queue: queue.Queue[tuple[str, str]] = queue.Queue()
        self.command_buttons: list[ttk.Button] = []

        frame = ttk.Frame(self.root, padding=12)
        frame.grid(sticky="nsew")

        ttk.Label(frame, text="Certeq Console", font=("", 16, "bold")).grid(
            row=0, column=0, columnspan=2, pady=(0, 8)
        )

        id_row = ttk.Frame(frame)
        id_row.grid(row=1, column=0, columnspan=2, pady=(0, 8))
        ttk.Label(id_row, text="Site ID:").pack(side="left", padx=(0, 6))
        self.site_id = ttk.Entry(id_row, width=12)
        self.site_id.pack(side="left")
        self.site_id.focus_set()

        for i, (caption, command) in enumerate(BUTTONS):
            btn = ttk.Button(
                frame, text=caption, width=18,
                command=lambda c=command: self.start(c),
            )
            btn.grid(row=2 + i // 2, column=i % 2, **PAD)
            self.command_buttons.append(btn)

        bottom = ttk.Frame(frame)
        bottom.grid(row=6, column=0, columnspan=2, pady=(8, 0))
        report_btn = ttk.Button(
            bottom, text="Daily Report", width=14, command=lambda: self.start("report")
        )
        report_btn.pack(side="left", padx=6)
        self.command_buttons.append(report_btn)
        ttk.Button(bottom, text="Login…", width=14, command=self.login_dialog).pack(
            side="left", padx=6
        )

        status_row = ttk.Frame(frame)
        status_row.grid(row=7, column=0, columnspan=2, sticky="w", pady=(10, 0))
        self.status_dot = tk.Label(status_row, text="●")
        self.status_dot.pack(side="left")
        self.status = ttk.Label(status_row, text="")
        self.status.pack(side="left", padx=(4, 0))

        self.refresh_login_status()
        self.root.after(100, self.poll)

    # ---- login state (mirrors the API_Login form's Active/Inactive label)

    def refresh_login_status(self) -> None:
        cfg = api._load_config()
        name = cfg.get("display_name") or cfg.get("username")
        try:
            has_token = bool(keyring.get_password(api.SERVICE, "token"))
        except Exception:
            has_token = False
        if name and has_token and time.time() < cfg.get("token_expiry", 0):
            self.status_dot.config(fg="#2e8b57")
            self.status.config(text=f"Logged in as {name} — token active")
        elif name:
            self.status_dot.config(fg="#cc9900")
            self.status.config(text=f"{name} — token expired (renews on next use)")
        else:
            self.status_dot.config(fg="#cc3333")
            self.status.config(text="Not logged in")

    def login_dialog(self) -> None:
        dialog = tk.Toplevel(self.root)
        dialog.title("Certeq Login")
        dialog.resizable(False, False)
        dialog.transient(self.root)
        dialog.grab_set()
        dialog.bind("<Escape>", lambda _e: dialog.destroy())

        body = ttk.Frame(dialog, padding=12)
        body.grid()
        ttk.Label(body, text="Username:").grid(row=0, column=0, sticky="e", **PAD)
        username = ttk.Entry(body, width=28)
        username.insert(0, api._load_config().get("username", ""))
        username.grid(row=0, column=1, **PAD)
        ttk.Label(body, text="Password:").grid(row=1, column=0, sticky="e", **PAD)
        password = ttk.Entry(body, width=28, show="•")
        password.grid(row=1, column=1, **PAD)
        (password if username.get() else username).focus_set()

        def submit(_e=None):
            user, pwd = username.get().strip(), password.get()
            if not user or not pwd:
                messagebox.showwarning(
                    "Certeq Login", "Username and password are required.", parent=dialog
                )
                return
            dialog.destroy()
            self.set_busy(True, "Logging in…")
            threading.Thread(
                target=self.login_worker, args=(user, pwd), daemon=True
            ).start()

        dialog.bind("<Return>", submit)
        buttons = ttk.Frame(body)
        buttons.grid(row=2, column=0, columnspan=2, pady=(8, 0))
        ttk.Button(buttons, text="Cancel", command=dialog.destroy).pack(side="left", padx=6)
        ttk.Button(buttons, text="Login", command=submit).pack(side="left", padx=6)

    def login_worker(self, user: str, pwd: str) -> None:
        try:
            data = api.login(user, pwd)
            name = data.get("display_name") or user
            self.queue.put(("ok", f"Logged in as {name}"))
        except Exception as exc:
            self.queue.put(("err", f"Login failed: {exc}"))

    # ---- email commands

    def start(self, command: str) -> None:
        site_id = self.site_id.get().strip()
        if command != "report" and not site_id:
            messagebox.showwarning("Certeq Console", "Enter a Site ID first.")
            return
        self.set_busy(True, "Fetching report data…")
        threading.Thread(
            target=self.email_worker, args=(command, site_id), daemon=True
        ).start()

    def email_worker(self, command: str, site_id: str) -> None:
        try:
            subject, to, cc, html, wants_signature = build_email(command, site_id or None)
            if wants_signature:
                html += outlook.signature()
            outlook.open_draft(subject, html, to, cc)
            self.queue.put(("ok", f"Draft opened: {subject}"))
        except SystemExit as exc:  # api.py reports not-logged-in / bad response this way
            self.queue.put(("err", str(exc)))
        except Exception as exc:
            self.queue.put(("err", f"{type(exc).__name__}: {exc}"))

    # ---- plumbing

    def set_busy(self, busy: bool, message: str = "") -> None:
        state = "disabled" if busy else "normal"
        for btn in self.command_buttons:
            btn.config(state=state)
        if busy:
            self.status_dot.config(fg="#888888")
            self.status.config(text=message)

    def poll(self) -> None:
        try:
            kind, message = self.queue.get_nowait()
        except queue.Empty:
            pass
        else:
            self.set_busy(False)
            self.refresh_login_status()
            if kind == "err":
                messagebox.showerror("Certeq Console", message)
            else:
                self.status.config(text=message)
        self.root.after(100, self.poll)

    def run(self) -> None:
        self.root.mainloop()


def main() -> None:
    App().run()
