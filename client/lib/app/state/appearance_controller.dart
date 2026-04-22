import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

final themeModeProvider = StateProvider<ThemeMode>((ref) => ThemeMode.dark);

const List<Locale> supportedAppLocales = <Locale>[
	Locale('en'),
	Locale('fr'),
	Locale('es'),
	Locale('de'),
	Locale('it'),
];

const String _localePreferenceKey = 'app_locale';

class AppLocaleController extends StateNotifier<Locale> {
	AppLocaleController() : super(const Locale('en')) {
		_load();
	}

	Future<void> _load() async {
		try {
			final prefs = await SharedPreferences.getInstance();
			final code = prefs.getString(_localePreferenceKey)?.trim();
			if (code != null && code.isNotEmpty) {
				state = Locale(code);
			}
		} catch (_) {
			// Keep the default locale if preferences cannot be read.
		}
	}

	Future<void> setLocale(Locale locale) async {
		state = locale;
		try {
			final prefs = await SharedPreferences.getInstance();
			await prefs.setString(_localePreferenceKey, locale.languageCode);
		} catch (_) {
			// Best-effort persistence.
		}
	}
}

final localeProvider = StateNotifierProvider<AppLocaleController, Locale>((ref) {
	return AppLocaleController();
});
