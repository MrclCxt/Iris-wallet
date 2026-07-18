# Glue de plugin Windows para o lwk (adicionado pelo projeto Iris Wallet).
# Compila o crate Rust via cargokit e empacota lwk.dll junto ao app.
cmake_minimum_required(VERSION 3.14)

set(PROJECT_NAME "lwk")
project(${PROJECT_NAME} LANGUAGES CXX)

include("../cargokit/cmake/cargokit.cmake")
apply_cargokit(${PROJECT_NAME} ../rust lwk "")

set(lwk_bundled_libraries
  "${${PROJECT_NAME}_cargokit_lib}"
  PARENT_SCOPE
)
