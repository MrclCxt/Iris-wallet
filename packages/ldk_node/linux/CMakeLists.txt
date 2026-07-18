# Glue de plugin Linux para o ldk_node (adicionado pelo projeto Iris Wallet).
# Compila o crate Rust via cargokit e empacota libldk_node.so junto ao app.
cmake_minimum_required(VERSION 3.14)

set(PROJECT_NAME "ldk_node")
project(${PROJECT_NAME} LANGUAGES CXX)

include("../cargokit/cmake/cargokit.cmake")
apply_cargokit(${PROJECT_NAME} ../rust ldk_node "")

set(ldk_node_bundled_libraries
  "${${PROJECT_NAME}_cargokit_lib}"
  PARENT_SCOPE
)
