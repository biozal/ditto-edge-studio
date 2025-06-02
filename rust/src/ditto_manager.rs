pub fn try_init_ditto(&self) -> Result<(), Box<dyn Error>> {
    let mut ditto = Ditto::builder()
        .with_identity(|root| OnlinePlayground::new(
            root,
            &self.config.app_id,
            &self.config.auth_token,
            false, // This is required to be set to false to use the correct URLs
            if self.config.auth_url.is_empty() {
                None
            } else {
                Some(&self.config.auth_url)
            }
        ))?
        .with_http_api(&self.config.http_api_url, &self.config.http_api_key)
        .with_offline_only(false)
        .with_encryption(false)
        .build()?;

    ditto.try_start_sync()?;
    self.ditto.set(Some(ditto))?;
    Ok(())
} 