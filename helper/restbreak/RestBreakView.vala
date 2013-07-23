/*
 * This file is part of Brain Break.
 * 
 * Brain Break is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 * 
 * Brain Break is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 * 
 * You should have received a copy of the GNU General Public License
 * along with Brain Break.  If not, see <http://www.gnu.org/licenses/>.
 */

/* TODO: Use a single persistent notification throughout a given break */

public class RestBreakView : TimerBreakView {
	protected RestBreakController rest_break {
		get { return (RestBreakController)this.break_controller; }
	}

	private string[] rest_quotes = {
		_("The quieter you become, the more you can hear."),
		_("Knock on the sky and listen to the sound."),
		_("So little time, so little to do."),
		_("Sometimes the questions are complicated and the answers are simple."),
		_("You cannot step into the same river twice."),
		_("The obstacle is the path."),
		_("No snowflake ever falls in the wrong place."),
		_("The energy of the mind is the essence of life.")
	};

	private bool is_postponed = false;
	private bool proceeding_happily = false;
	
	public RestBreakView(BreakType break_type, RestBreakController rest_break, UIManager ui_manager) {
		base(break_type, rest_break, ui_manager);
		this.focus_priority = FocusPriority.HIGH;

		this.focused_and_activated.connect(this.focused_and_activated_cb);
		this.lost_ui_focus.connect(this.lost_ui_focus_cb);
		this.rest_break.finished.connect(this.finished_cb);
	}

	protected new void show_break_notification(Notify.Notification notification, bool allow_postpone) {
		if (allow_postpone) {
			notification.add_action("postpone", _("Remind me later"), this.notification_action_postpone_cb);
		}
		base.show_break_notification(notification);
	}

	private void show_start_notification() {
		// FIXME: Should say how long the break is?
		var notification = this.build_common_notification(
			_("Time for a break"),
			_("It’s time to take a break. Get away from the computer for a little while!"),
			"alarm-symbolic"
		);
		notification.set_urgency(Notify.Urgency.NORMAL);
		notification.set_hint("sound-name", "message");
		notification.closed.connect(this.notification_closed_cb);
		this.show_break_notification(notification, true);
	}

	private void show_interrupted_notification() {
		int time_remaining = this.rest_break.get_time_remaining();
		int start_time = this.rest_break.get_current_duration();
		string countdown = NaturalTime.instance.get_countdown_for_seconds_with_start(
			time_remaining, start_time);
		var notification = this.build_common_notification(
			_("Break interrupted"),
			_("%s of break remaining").printf(countdown),
			"alarm-symbolic"
		);
		notification.set_urgency(Notify.Urgency.NORMAL);
		this.show_break_notification(notification, false);
	}

	private void show_overdue_notification() {
		int time_since_start = this.rest_break.get_seconds_since_start();
		string delay_string = NaturalTime.instance.get_simplest_label_for_seconds(
			time_since_start);
		var notification = this.build_common_notification(
			_("Overdue break"),
			_("You were due to take a break %s ago").printf(delay_string),
			"alarm-symbolic"
		);
		notification.set_urgency(Notify.Urgency.NORMAL);
		this.show_break_notification(notification, false);
	}

	private void show_finished_notification() {
		var notification = this.build_common_notification(
			_("Break is over"),
			_("Your break time has ended"),
			"alarm-symbolic"
		);
		notification.set_urgency(Notify.Urgency.NORMAL);
		this.show_lock_notification(notification);

		this.play_sound_from_id("complete");
	}

	private void focused_and_activated_cb() {
		this.is_postponed = false;
		this.proceeding_happily = false;

		var status_widget = new TimerBreakStatusWidget(this.rest_break);
		int quote_number = Random.int_range(0, this.rest_quotes.length);
		string random_quote = this.rest_quotes[quote_number];
		status_widget.set_message(random_quote);
		this.set_overlay(status_widget);

		if (! this.overlay_is_visible()) {
			this.show_start_notification();

			Timeout.add_seconds(this.get_lead_in_seconds(), () => {
				this.reveal_overlay();
				return false;
			});
		}

		this.rest_break.counting.connect(this.counting_cb);
		this.rest_break.delayed.connect(this.delayed_cb);
		this.rest_break.current_duration_changed.connect(this.current_duration_changed_cb);
	}

	private void lost_ui_focus_cb() {
		this.rest_break.counting.disconnect(this.counting_cb);
		this.rest_break.delayed.disconnect(this.delayed_cb);
		this.rest_break.current_duration_changed.disconnect(this.current_duration_changed_cb);
	}

	private void finished_cb(BreakController.FinishedReason reason, bool was_active) {
		if (reason == BreakController.FinishedReason.SATISFIED && was_active) {
			this.show_finished_notification();
		} else {
			this.hide_notification();
		}
	}

	private void counting_cb(int lap_time, int total_time) {
		this.proceeding_happily = lap_time > 30;

		if (this.has_ui_focus() && this.proceeding_happily) {
			this.is_postponed = false;
			// TODO: Make a sound
			if (! SessionStatus.instance.is_locked()) {
				SessionStatus.instance.lock_screen();
			}
		}
	}

	private void delayed_cb(int lap_time, int total_time) {
		if (! this.is_postponed) {
			if (this.proceeding_happily) {
				// Show a "Break interrupted" notification if the break has
				// been counting down happily until now
				this.show_interrupted_notification();
			} else if (this.seconds_since_last_break_notification() > 60) {
				// Show an "Overdue break" notification every minute if the
				// break is being delayed.
				this.show_overdue_notification();
			}
		}

		this.proceeding_happily = false;
	}

	private void current_duration_changed_cb() {
		this.shake_overlay();
	}

	private void notification_closed_cb() {
		// If the notification is dismissed, we assume the user is cutting the break short.
		// Since we're using persistent notifications, this requires the user to explicitly
		// remove the notification from its context menu in the message tray.
		if (this.notification.get_closed_reason() == 2) {
			// Notification closed reason code 2: dismissed by the user
			this.rest_break.skip();
		}
	}

	private void notification_action_postpone_cb() {
		this.is_postponed = true;
		this.hide_notification();

		Timeout.add_seconds(60, () => {
			if (this.is_postponed) {
				this.show_overdue_notification();
				this.is_postponed = false;
			}
			return false;
		});
	}
}

