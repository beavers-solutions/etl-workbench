def build_message(value: str) -> dict[str, str]:
    """Return a deliberately small XCom-safe value."""
    return {"message": value.strip()}
