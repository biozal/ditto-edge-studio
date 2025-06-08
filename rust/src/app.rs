use std::collections::HashMap;

pub enum CurrentScreen {
    AppListing,
    AppEditor,
    AppDeletion,
	Main,
}

pub struct App {
	pub selected_app: Option<DittoAppConfig>,
	pub current_screen: CurrentScreen,
}

