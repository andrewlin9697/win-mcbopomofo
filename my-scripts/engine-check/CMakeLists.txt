# 只在 CI(ubuntu)用:把官方的 src/Server/Engine 當子目錄編進來,不修改官方檔案。
cmake_minimum_required(VERSION 3.10)
project(MyPhrasesEngineCheck CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

set(ENGINE_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../../src/Server/Engine")
add_subdirectory("${ENGINE_DIR}" engine)

add_executable(engine_check engine_check.cpp)
target_include_directories(engine_check PRIVATE "${ENGINE_DIR}")
target_link_libraries(engine_check McBopomofoLMLib gramambular2_lib)
